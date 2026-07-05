#include <QGuiApplication>
#include <QQuickView>
#include <QUrl>

#include "transcriber.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("voicenote.yourname"));
    app.setOrganizationName(QStringLiteral("voicenote.yourname"));

    qmlRegisterType<Transcriber>("VoiceNote", 1, 0, "Transcriber");

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setSource(QUrl(QStringLiteral("qrc:///Main.qml")));
    view.show();

    return app.exec();
}
