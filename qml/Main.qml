import QtQuick 2.12
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import VoiceNote 1.0

MainView {
    id: root
    objectName: "mainView"
    applicationName: "voicenote.yourname"

    width: units.gu(45)
    height: units.gu(75)

    Transcriber { id: stt }

    Connections {
        target: stt
        onError: statusLabel.color = theme.palette.normal.negative
        onStatusTextChanged: statusLabel.color = theme.palette.normal.backgroundSecondaryText
    }

    Page {
        anchors.fill: parent
        header: PageHeader {
            id: header
            title: i18n.tr("VoiceNote")
        }

        Column {
            anchors {
                top: header.bottom
                left: parent.left
                right: parent.right
                margins: units.gu(2)
            }
            spacing: units.gu(2)

            // ---- one-time model download ------------------------------
            Column {
                width: parent.width
                spacing: units.gu(1)
                visible: !stt.modelReady

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: i18n.tr("First run: download the speech model (~75 MB, one time). Everything runs offline afterwards.")
                }
                Button {
                    text: stt.downloading
                          ? i18n.tr("Downloading… %1%").arg(Math.round(stt.downloadProgress * 100))
                          : i18n.tr("Download model")
                    color: theme.palette.normal.positive
                    enabled: !stt.downloading
                    onClicked: stt.downloadModel()
                }
                ProgressBar {
                    width: parent.width
                    visible: stt.downloading
                    value: stt.downloadProgress
                }
            }

            // ---- push-to-talk button ----------------------------------
            Item {
                width: parent.width
                height: units.gu(18)
                visible: stt.modelReady

                Rectangle {
                    id: pttButton
                    anchors.centerIn: parent
                    width: units.gu(16)
                    height: width
                    radius: width / 2
                    color: stt.recording
                           ? theme.palette.normal.negative
                           : stt.busy ? theme.palette.normal.base
                                      : theme.palette.normal.positive
                    scale: pttArea.pressed ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }

                    Label {
                        anchors.centerIn: parent
                        text: stt.recording ? i18n.tr("Listening")
                              : stt.busy   ? i18n.tr("Working…")
                                           : i18n.tr("Hold to talk")
                        color: "white"
                        fontSize: "large"
                    }

                    MouseArea {
                        id: pttArea
                        anchors.fill: parent
                        enabled: !stt.busy
                        onPressed: stt.startRecording()
                        onReleased: stt.stopAndTranscribe()
                        onCanceled: stt.cancelRecording()
                    }
                }

                ActivityIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    running: stt.busy
                    visible: stt.busy
                }
            }

            Label {
                id: statusLabel
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: stt.statusText
            }

            // ---- transcript -------------------------------------------
            TextArea {
                id: transcriptArea
                width: parent.width
                height: units.gu(16)
                text: stt.transcript
                placeholderText: i18n.tr("Your words appear here…")
                // editable so you can fix small mistakes before saving
            }

            Row {
                spacing: units.gu(1)
                anchors.horizontalCenter: parent.horizontalCenter

                Button {
                    text: i18n.tr("Save note")
                    color: theme.palette.normal.positive
                    enabled: transcriptArea.text.trim().length > 0
                    onClicked: {
                        if (stt.saveNote(transcriptArea.text)) {
                            transcriptArea.text = ""
                            statusLabel.text = i18n.tr("Note saved")
                        }
                    }
                }
                Button {
                    text: i18n.tr("Copy")
                    enabled: transcriptArea.text.trim().length > 0
                    onClicked: {
                        transcriptArea.selectAll()
                        transcriptArea.copy()
                        transcriptArea.deselect()
                    }
                }
                Button {
                    text: i18n.tr("Clear")
                    onClicked: transcriptArea.text = ""
                }
            }

            // ---- Phase 2 teaser: naive intent preview -----------------
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                fontSize: "small"
                color: theme.palette.normal.backgroundTertiaryText
                visible: intentText !== ""
                text: intentText
                property string intentText: {
                    var t = transcriptArea.text.toLowerCase().trim()
                    if (t.indexOf("call ") === 0)
                        return i18n.tr("Detected intent: CALL \u2192 will match \"%1\" against contacts (Phase 3)").arg(t.substring(5))
                    if (t.indexOf("text ") === 0 || t.indexOf("message ") === 0)
                        return i18n.tr("Detected intent: MESSAGE (Phase 3)")
                    if (t.indexOf("note ") === 0 || t.indexOf("note:") === 0)
                        return i18n.tr("Detected intent: NOTE")
                    if (t.indexOf("remind") === 0 || t.indexOf("calendar") !== -1 || t.indexOf("event") === 0)
                        return i18n.tr("Detected intent: CALENDAR EVENT (Phase 3)")
                    return ""
                }
            }
        }
    }
}
