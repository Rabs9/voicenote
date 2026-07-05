#pragma once

#include <QObject>
#include <QByteArray>
#include <QString>
#include <QFutureWatcher>

class QAudioInput;
class QIODevice;
class QNetworkAccessManager;
class QNetworkReply;
struct whisper_context;

/*
 * Push-to-talk transcriber.
 *  - startRecording(): opens the mic at 16 kHz / mono / s16le and buffers PCM
 *  - stopAndTranscribe(): stops capture and runs whisper.cpp in a worker
 *    thread; result lands in `transcript`
 *  - downloadModel(): one-time fetch of the ggml model into app data dir
 */
class Transcriber : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool modelReady READ modelReady NOTIFY modelReadyChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(qreal downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(QString transcript READ transcript NOTIFY transcriptChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString modelName READ modelName WRITE setModelName NOTIFY modelNameChanged)

public:
    explicit Transcriber(QObject *parent = nullptr);
    ~Transcriber() override;

    bool recording() const { return m_recording; }
    bool busy() const { return m_busy; }
    bool downloading() const { return m_downloading; }
    qreal downloadProgress() const { return m_downloadProgress; }
    QString transcript() const { return m_transcript; }
    QString statusText() const { return m_statusText; }
    QString modelName() const { return m_modelName; }
    void setModelName(const QString &name);
    bool modelReady() const;

    Q_INVOKABLE void startRecording();
    Q_INVOKABLE void stopAndTranscribe();
    Q_INVOKABLE void cancelRecording();
    Q_INVOKABLE void downloadModel();
    Q_INVOKABLE QString modelPath() const;
    Q_INVOKABLE bool saveNote(const QString &text) const;

signals:
    void recordingChanged();
    void busyChanged();
    void modelReadyChanged();
    void downloadingChanged();
    void downloadProgressChanged();
    void transcriptChanged();
    void statusTextChanged();
    void modelNameChanged();
    void error(const QString &message);

private:
    void setStatus(const QString &s);
    void runWhisperAsync(QByteArray pcm);
    static QString transcribePcm(const QString &modelFile, const QByteArray &pcm,
                                 whisper_context **ctxCache);

    // audio
    QAudioInput *m_audio = nullptr;
    QIODevice *m_audioDev = nullptr;
    QByteArray m_pcmBuffer;
    bool m_recording = false;

    // whisper
    bool m_busy = false;
    QString m_transcript;
    QString m_modelName = QStringLiteral("ggml-tiny.en.bin");
    whisper_context *m_ctx = nullptr;   // cached across runs (load once)
    QFutureWatcher<QString> m_watcher;

    // download
    QNetworkAccessManager *m_net = nullptr;
    QNetworkReply *m_reply = nullptr;
    bool m_downloading = false;
    qreal m_downloadProgress = 0.0;

    QString m_statusText;
};
