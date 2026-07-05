#include "transcriber.h"

#include <QAudioInput>
#include <QAudioFormat>
#include <QAudioDeviceInfo>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QDateTime>
#include <QStandardPaths>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QtConcurrent/QtConcurrent>
#include <QDebug>

#include <vector>

#include "whisper.h"

static const int kSampleRate = 16000; // whisper expects 16 kHz mono

// Model download source (one-time; app is fully offline afterwards).
static QString modelUrl(const QString &name)
{
    return QStringLiteral(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/%1").arg(name);
}

Transcriber::Transcriber(QObject *parent)
    : QObject(parent)
{
    m_net = new QNetworkAccessManager(this);

    connect(&m_watcher, &QFutureWatcher<QString>::finished, this, [this]() {
        m_busy = false;
        emit busyChanged();
        m_transcript = m_watcher.result().trimmed();
        emit transcriptChanged();
        setStatus(m_transcript.isEmpty() ? tr("Heard nothing intelligible")
                                         : tr("Done"));
    });

    setStatus(modelReady() ? tr("Ready — hold the button and speak")
                           : tr("Model not downloaded yet"));
}

Transcriber::~Transcriber()
{
    if (m_ctx) {
        whisper_free(m_ctx);
        m_ctx = nullptr;
    }
}

void Transcriber::setModelName(const QString &name)
{
    if (name == m_modelName)
        return;
    m_modelName = name;
    // Different model file -> drop the cached context
    if (m_ctx) {
        whisper_free(m_ctx);
        m_ctx = nullptr;
    }
    emit modelNameChanged();
    emit modelReadyChanged();
}

QString Transcriber::modelPath() const
{
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/models");
    return dir + QLatin1Char('/') + m_modelName;
}

bool Transcriber::modelReady() const
{
    return QFile::exists(modelPath());
}

void Transcriber::setStatus(const QString &s)
{
    if (s == m_statusText)
        return;
    m_statusText = s;
    emit statusTextChanged();
}

// --------------------------------------------------------------------------
// Recording
// --------------------------------------------------------------------------

void Transcriber::startRecording()
{
    if (m_recording || m_busy)
        return;
    if (!modelReady()) {
        emit error(tr("Download the speech model first"));
        return;
    }

    QAudioFormat fmt;
    fmt.setSampleRate(kSampleRate);
    fmt.setChannelCount(1);
    fmt.setSampleSize(16);
    fmt.setCodec(QStringLiteral("audio/pcm"));
    fmt.setByteOrder(QAudioFormat::LittleEndian);
    fmt.setSampleType(QAudioFormat::SignedInt);

    QAudioDeviceInfo dev = QAudioDeviceInfo::defaultInputDevice();
    if (!dev.isFormatSupported(fmt)) {
        // PulseAudio usually resamples for us; fall back to nearest just in case.
        qWarning() << "16kHz mono not natively supported, using nearest format";
        fmt = dev.nearestFormat(fmt);
    }

    m_pcmBuffer.clear();
    m_audio = new QAudioInput(dev, fmt, this);
    m_audioDev = m_audio->start();
    if (!m_audioDev) {
        emit error(tr("Could not open microphone"));
        delete m_audio;
        m_audio = nullptr;
        return;
    }

    connect(m_audioDev, &QIODevice::readyRead, this, [this]() {
        if (m_audioDev)
            m_pcmBuffer.append(m_audioDev->readAll());
    });

    m_recording = true;
    emit recordingChanged();
    setStatus(tr("Listening…"));
}

void Transcriber::cancelRecording()
{
    if (!m_recording)
        return;
    m_audio->stop();
    m_audio->deleteLater();
    m_audio = nullptr;
    m_audioDev = nullptr;
    m_pcmBuffer.clear();
    m_recording = false;
    emit recordingChanged();
    setStatus(tr("Cancelled"));
}

void Transcriber::stopAndTranscribe()
{
    if (!m_recording)
        return;

    m_audio->stop();
    if (m_audioDev)
        m_pcmBuffer.append(m_audioDev->readAll());
    m_audio->deleteLater();
    m_audio = nullptr;
    m_audioDev = nullptr;
    m_recording = false;
    emit recordingChanged();

    // ~0.4 s minimum, otherwise whisper hallucinates on silence
    if (m_pcmBuffer.size() < kSampleRate * 2 * 4 / 10) {
        setStatus(tr("Too short — hold the button while you speak"));
        return;
    }

    runWhisperAsync(m_pcmBuffer);
    m_pcmBuffer.clear();
}

// --------------------------------------------------------------------------
// Whisper
// --------------------------------------------------------------------------

void Transcriber::runWhisperAsync(QByteArray pcm)
{
    m_busy = true;
    emit busyChanged();
    setStatus(tr("Transcribing…"));

    const QString path = modelPath();
    whisper_context **cache = &m_ctx;
    m_watcher.setFuture(QtConcurrent::run([path, pcm, cache]() {
        return transcribePcm(path, pcm, cache);
    }));
}

QString Transcriber::transcribePcm(const QString &modelFile,
                                   const QByteArray &pcm,
                                   whisper_context **ctxCache)
{
    // Lazy-load and cache the model (loading tiny.en takes ~1s; keep it)
    if (!*ctxCache) {
        whisper_context_params cparams = whisper_context_default_params();
        *ctxCache = whisper_init_from_file_with_params(
            modelFile.toUtf8().constData(), cparams);
        if (!*ctxCache) {
            qWarning() << "Failed to load whisper model" << modelFile;
            return QString();
        }
    }

    // s16le -> float32
    const int16_t *samples =
        reinterpret_cast<const int16_t *>(pcm.constData());
    const size_t n = pcm.size() / sizeof(int16_t);
    std::vector<float> pcmf32(n);
    for (size_t i = 0; i < n; ++i)
        pcmf32[i] = samples[i] / 32768.0f;

    whisper_full_params params =
        whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.language        = "en";
    params.translate       = false;
    params.print_progress  = false;
    params.print_realtime  = false;
    params.print_special   = false;
    params.no_timestamps   = true;
    params.single_segment  = false;
    // Snapdragon 732G: 2x A76 + 6x A55. 4 threads is a decent balance.
    params.n_threads       = 4;

    if (whisper_full(*ctxCache, params, pcmf32.data(),
                     static_cast<int>(pcmf32.size())) != 0) {
        qWarning() << "whisper_full failed";
        return QString();
    }

    QString out;
    const int segs = whisper_full_n_segments(*ctxCache);
    for (int i = 0; i < segs; ++i)
        out += QString::fromUtf8(whisper_full_get_segment_text(*ctxCache, i));
    return out;
}

// --------------------------------------------------------------------------
// Model download (one time)
// --------------------------------------------------------------------------

void Transcriber::downloadModel()
{
    if (m_downloading || modelReady())
        return;

    QDir().mkpath(QFileInfo(modelPath()).absolutePath());

    QNetworkRequest req{QUrl(modelUrl(m_modelName))};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_net->get(req);
    m_downloading = true;
    m_downloadProgress = 0.0;
    emit downloadingChanged();
    emit downloadProgressChanged();
    setStatus(tr("Downloading model…"));

    auto *file = new QSaveFile(modelPath(), m_reply);
    if (!file->open(QIODevice::WriteOnly)) {
        emit error(tr("Cannot write model file"));
        m_reply->abort();
        return;
    }

    connect(m_reply, &QNetworkReply::readyRead, this, [this, file]() {
        file->write(m_reply->readAll());
    });
    connect(m_reply, &QNetworkReply::downloadProgress, this,
            [this](qint64 got, qint64 total) {
        m_downloadProgress = total > 0 ? qreal(got) / qreal(total) : 0.0;
        emit downloadProgressChanged();
    });
    connect(m_reply, &QNetworkReply::finished, this, [this, file]() {
        m_downloading = false;
        emit downloadingChanged();
        if (m_reply->error() == QNetworkReply::NoError) {
            file->write(m_reply->readAll());
            file->commit();
            emit modelReadyChanged();
            setStatus(tr("Model ready — hold the button and speak"));
        } else {
            setStatus(tr("Download failed: %1").arg(m_reply->errorString()));
            emit error(m_reply->errorString());
        }
        m_reply->deleteLater();
        m_reply = nullptr;
    });
}

// --------------------------------------------------------------------------
// Notes (Phase 1: plain text files in app data)
// --------------------------------------------------------------------------

bool Transcriber::saveNote(const QString &text) const
{
    if (text.trimmed().isEmpty())
        return false;
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/notes");
    QDir().mkpath(dir);
    const QString fname = dir + QStringLiteral("/note-%1.txt")
        .arg(QDateTime::currentDateTime().toString(
             QStringLiteral("yyyyMMdd-HHmmss")));
    QFile f(fname);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    f.write(text.toUtf8());
    f.write("\n");
    return true;
}
