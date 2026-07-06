#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QUrl>

#include "transcriber.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("voicenote.falcon"));
    app.setOrganizationName(QStringLiteral("voicenote.falcon"));

    qmlRegisterType<Transcriber>("VoiceNote", 1, 0, "Transcriber");

    // "VoiceNote Button" launcher entry starts us with --button:
    // minimal push-to-talk-only UI
    const bool buttonMode = app.arguments().contains(QStringLiteral("--button"));

    QQuickView view;
    view.rootContext()->setContextProperty(QStringLiteral("buttonMode"), buttonMode);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setSource(QUrl(QStringLiteral("qrc:///Main.qml")));
    view.show();

    return app.exec();
}
