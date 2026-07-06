import QtQuick 2.12
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import QtOrganizer 5.0
import VoiceNote 1.0

MainView {
    id: root
    objectName: "mainView"
    applicationName: "voicenote.falcon"
    anchorToKeyboard: true   // resize content when the on-screen keyboard opens

    width: units.gu(45)
    height: units.gu(75)

    Transcriber { id: stt }

    // System alarm (rings via the Clock app)
    Alarm {
        id: sysAlarm
        onStatusChanged: {
            if (status !== Alarm.Ready || operation <= Alarm.NoOperation)
                return
            if (error === Alarm.NoError)
                statusLabel.text = i18n.tr("Alarm set: %1").arg(root.pendingAlarmText)
            else
                statusLabel.text = i18n.tr("Failed to set alarm (error %1)").arg(error)
        }
    }
    property string pendingAlarmText: ""

    // System calendar (EDS — same backend the Calendar app reads)
    OrganizerModel {
        id: organizer
        manager: "eds"
        autoUpdate: false
    }

    // Shared natural-language parser:
    // "…tomorrow at 6 am" / "…february 14th for valentines day at 9 00 am"
    // Returns { date, label } or { error }
    function parseWhen(restStr) {
        var rest = " " + restStr + " "
        var now = new Date()

        // ---- time: "at 9 00 am" / "at 6am" / "at 18 30" ----
        var tm = rest.match(/ at (\d{1,2}) ?(\d{2})? ?(am|pm|a m|p m)? /)
        if (!tm)
            return { error: i18n.tr("Couldn't hear a time — include e.g. \"at 6 am\"") }
        var hours = parseInt(tm[1])
        var mins  = tm[2] ? parseInt(tm[2]) : 0
        var ap = (tm[3] || "").replace(/ /g, "")
        if (ap === "pm" && hours < 12) hours += 12
        if (ap === "am" && hours === 12) hours = 0
        rest = rest.replace(tm[0], " ")

        // ---- date: tomorrow / today / month+day / weekday ----
        var date = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var dateKind = "none"
        if (rest.indexOf(" tomorrow ") !== -1) {
            date.setDate(date.getDate() + 1)
            dateKind = "tomorrow"
            rest = rest.replace(" tomorrow ", " ")
        } else if (rest.indexOf(" today ") !== -1) {
            dateKind = "today"
            rest = rest.replace(" today ", " ")
        } else {
            var months = ["january","february","march","april","may","june",
                          "july","august","september","october","november","december"]
            var dm = rest.match(/ (?:for |on )?(january|february|march|april|may|june|july|august|september|october|november|december) (\d{1,2})(?:st|nd|rd|th)? /)
            if (dm) {
                date = new Date(now.getFullYear(), months.indexOf(dm[1]), parseInt(dm[2]))
                dateKind = "month"
                rest = rest.replace(dm[0], " ")
            } else {
                var days = ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]
                for (var d = 0; d < days.length; d++) {
                    if (rest.indexOf(" " + days[d] + " ") !== -1) {
                        var delta = (d - now.getDay() + 7) % 7
                        if (delta === 0) delta = 7
                        date.setDate(date.getDate() + delta)
                        dateKind = "weekday"
                        rest = rest.replace(" " + days[d] + " ", " ")
                        break
                    }
                }
            }
        }

        date.setHours(hours, mins, 0, 0)

        if (date <= now) {
            if (dateKind === "month")
                date.setFullYear(date.getFullYear() + 1)   // e.g. Feb 14 already passed
            else if (dateKind === "none")
                date.setDate(date.getDate() + 1)           // bare time -> next occurrence
            else
                return { error: i18n.tr("That time has already passed") }
        }

        // ---- label: whatever is left, minus filler words ----
        var label = rest.replace(/\s+/g, " ").trim()
        while (label.match(/^(?:for|on|the) /))
            label = label.replace(/^(?:for|on|the) /, "")
        label = label.replace(/ (?:for|on|the)$/, "").trim()

        return { date: date, label: label }
    }

    function handleAlarm(restStr) {
        var w = parseWhen(restStr)
        if (w.error) {
            statusLabel.text = w.error
            return
        }
        var label = w.label.length > 0 ? w.label : i18n.tr("VoiceNote alarm")

        root.pendingAlarmText = Qt.formatDateTime(w.date, "ddd, MMM d 'at' h:mm ap")
                                + " \u2014 " + label
        statusLabel.text = i18n.tr("Setting alarm: %1…").arg(root.pendingAlarmText)
        console.log("alarm: " + w.date + " label='" + label + "'")

        sysAlarm.reset()
        sysAlarm.date = w.date
        sysAlarm.message = label
        sysAlarm.type = Alarm.OneTime
        sysAlarm.save()
    }

    function handleEvent(restStr) {
        var w = parseWhen(restStr)
        if (w.error) {
            statusLabel.text = w.error
            return
        }
        var label = w.label.length > 0 ? w.label : i18n.tr("VoiceNote event")

        var ev = Qt.createQmlObject(
            "import QtOrganizer 5.0; Event {}", organizer)
        ev.displayLabel = label
        ev.startDateTime = w.date
        ev.endDateTime = new Date(w.date.getTime() + 60 * 60 * 1000) // 1 hour
        organizer.saveItem(ev)

        statusLabel.text = i18n.tr("Event added: %1 \u2014 %2")
            .arg(Qt.formatDateTime(w.date, "ddd, MMM d 'at' h:mm ap"))
            .arg(label)
        console.log("event: " + w.date + " label='" + label + "'")
    }

    // app name -> launch URL (built from what's installed on this phone)
    property var appMap: {
        // click apps
        "camera":        "appid://camera.ubports/camera/current-user-version",
        "barcode":       "appid://camera.ubports/barcode-reader/current-user-version",
        "qr":            "appid://camera.ubports/barcode-reader/current-user-version",
        "clock":         "appid://clock.ubports/clock/current-user-version",
        "alarm":         "appid://clock.ubports/clock/current-user-version",
        "calculator":    "appid://calculator.ubports/calculator/current-user-version",
        "calendar":      "appid://calendar.ubports/calendar/current-user-version",
        "gallery":       "appid://gallery.ubports/gallery/current-user-version",
        "photos":        "appid://gallery.ubports/gallery/current-user-version",
        "files":         "appid://filemanager.ubports/filemanager/current-user-version",
        "file manager":  "appid://filemanager.ubports/filemanager/current-user-version",
        "music":         "appid://music.ubports/music/current-user-version",
        "weather":       "appid://weather.ubports/weather/current-user-version",
        "terminal":      "appid://terminal.ubports/terminal/current-user-version",
        "browser":       "appid://morph-browser-qt6.ubports/morph-browser/current-user-version",
        "web":           "appid://morph-browser-qt6.ubports/morph-browser/current-user-version",
        "store":         "appid://openstore.openstore-team/openstore/current-user-version",
        "open store":    "appid://openstore.openstore-team/openstore/current-user-version",
        "app store":     "appid://openstore.openstore-team/openstore/current-user-version",
        "maps":          "appid://pure-maps.jonnius/pure-maps/current-user-version",
        "signal":        "appid://signalut.pparent/signallauncher/current-user-version",
        "mail":          "appid://proton-mail.josele13/proton-mail/current-user-version",
        "email":         "appid://proton-mail.josele13/proton-mail/current-user-version",
        "proton":        "appid://proton-mail.josele13/proton-mail/current-user-version",
        "youtube":       "appid://youtube-web.mateo-salta/youtube-web/current-user-version",
        "recorder":      "appid://audio-recorder.luksus/Recorder/current-user-version",
        "duolingo":      "appid://duolingo.manuelboe/duolingo/current-user-version",
        "tailscale":     "appid://tailscale-app.colocoluicultum/tailscale-app/current-user-version",
        "trading":       "appid://abundance-trading.colocoluicultum/abundance-trading/current-user-version",
        "codium":        "appid://codium.vscodium.com/code/current-user-version",
        "code":          "appid://codium.vscodium.com/code/current-user-version",
        "tweak tool":    "appid://ut-tweak-tool.sverzegnassi/ut-tweak-tool/current-user-version",
        // system (legacy) apps
        "phone":         "application:///lomiri-dialer-app.desktop",
        "dialer":        "application:///lomiri-dialer-app.desktop",
        "messages":      "application:///lomiri-messaging-app.desktop",
        "messaging":     "application:///lomiri-messaging-app.desktop",
        "texts":         "application:///lomiri-messaging-app.desktop",
        "contacts":      "application:///lomiri-addressbook-app.desktop",
        "address book":  "application:///lomiri-addressbook-app.desktop",
        "settings":      "settings:///"
    }

    // Returns true if the text was a command and was executed.
    function tryCommand(text) {
        var t = text.toLowerCase().replace(/[^a-z0-9 ]/g, " ")
                     .replace(/\s+/g, " ").trim()

        // "set (an) alarm …" / "wake me up …" -> system alarm
        var a = t.match(/^set (?:an? )?alarm (.+)$/) || t.match(/^wake me up (.+)$/)
        if (a) {
            handleAlarm(a[1])
            return true
        }

        // "add/create event|appointment|meeting …" -> calendar event
        var e = t.match(/^(?:add|create|set|new) (?:an? )?(?:event|appointment|meeting) (.+)$/)
             || t.match(/^add to (?:the )?calendar (.+)$/)
        if (e) {
            handleEvent(e[1])
            return true
        }

        // "search (for) X" -> web search
        var s = t.match(/^search (?:for )?(.+)$/)
        if (s) {
            statusLabel.text = i18n.tr("Searching for \"%1\"…").arg(s[1])
            Qt.openUrlExternally("https://duckduckgo.com/?q="
                                 + encodeURIComponent(s[1]))
            return true
        }

        // "open / launch / start / go to X" -> app launch
        var m = t.match(/^(?:open|launch|start|go to) (.+)$/)
        if (!m)
            return false

        var name = m[1]
        var url = appMap[name]
        if (!url) {
            // fuzzy: spoken name contains a known key or vice versa
            var keys = Object.keys(appMap)
            for (var i = 0; i < keys.length; i++) {
                if (name.indexOf(keys[i]) !== -1 || keys[i].indexOf(name) !== -1) {
                    url = appMap[keys[i]]
                    name = keys[i]
                    break
                }
            }
        }

        if (url) {
            statusLabel.text = i18n.tr("Opening %1…").arg(name)
            console.log("launching: " + url)
            Qt.openUrlExternally(url)
        } else {
            statusLabel.text = i18n.tr("Don't know an app called \"%1\"").arg(name)
        }
        return true
    }

    Connections {
        target: stt
        onError: statusLabel.color = theme.palette.normal.negative
        onStatusTextChanged: {
            statusLabel.color = theme.palette.normal.backgroundSecondaryText
            statusLabel.text = stt.statusText
        }
        onTranscriptChanged: {
            // Route dictation to whichever page is active
            if (pageStack.currentPage === buttonPage) {
                // widget mode: command or auto-saved note, nothing else
                if (root.tryCommand(stt.transcript)) {
                    buttonPage.lastResult = statusLabel.text
                } else if (stt.saveNote(stt.transcript)) {
                    buttonPage.lastResult = i18n.tr("Note saved: \u201c%1\u201d")
                        .arg(stt.transcript.length > 60
                             ? stt.transcript.substring(0, 60) + "\u2026"
                             : stt.transcript)
                }
            } else if (pageStack.currentPage === editorPage) {
                var t = editorArea.text.trim()
                editorArea.text = t.length > 0 ? t + " " + stt.transcript
                                               : stt.transcript
                editorArea.cursorPosition = editorArea.text.length
            } else {
                // main page: commands take priority, otherwise it's a note
                if (!root.tryCommand(stt.transcript))
                    transcriptArea.text = stt.transcript
            }
        }
    }

    PageStack {
        id: pageStack
        Component.onCompleted: push(buttonMode ? buttonPage : recorderPage)

        // ============================================================
        // PAGE 1: Recorder
        // ============================================================
        Page {
            id: recorderPage
            visible: false
            header: PageHeader {
                id: header
                title: i18n.tr("VoiceNote")
                leadingActionBar.actions: [
                    Action {
                        iconName: "settings"
                        text: i18n.tr("Settings")
                        onTriggered: pageStack.push(settingsPage)
                    }
                ]
                trailingActionBar.actions: [
                    Action {
                        iconName: "note"
                        text: i18n.tr("Notes")
                        onTriggered: pageStack.push(notesPage)
                    }
                ]
            }

            Column {
                anchors {
                    top: header.bottom
                    left: parent.left
                    right: parent.right
                    margins: units.gu(2)
                }
                spacing: units.gu(2)

                // ---- one-time model download --------------------------
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

                // ---- push-to-talk button ------------------------------
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
                    // text set via Connections (bindings break when assigned from JS)
                    Component.onCompleted: text = stt.statusText
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundTertiaryText
                    visible: stt.modelReady
                    text: i18n.tr("Tip: \"open camera\" \u00b7 \"search for …\" \u00b7 \"set alarm for tomorrow at 6 am\" \u00b7 \"add event dentist on friday at 2 pm\"")
                }

                // ---- transcript ---------------------------------------
                TextArea {
                    id: transcriptArea
                    width: parent.width
                    height: units.gu(16)
                    placeholderText: i18n.tr("Your words appear here…")
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
            }
        }

        // ============================================================
        // PAGE 2: Notes Browser
        // ============================================================
        Page {
            id: notesPage
            visible: false
            header: PageHeader {
                id: notesHeader
                title: i18n.tr("Saved Notes")
                trailingActionBar.actions: [
                    Action {
                        iconName: "add"
                        text: i18n.tr("New note")
                        // empty filename = new-note mode; file created on Save
                        onTriggered: notesPage.openEditor("")
                    }
                ]
            }

            property var notesList: []

            function refresh() {
                notesList = stt.listNotes()
            }

            function openEditor(filename) {
                editorPage.filename = filename
                // always read fresh from disk — delegate copies can be stale
                editorArea.text = filename === "" ? "" : stt.readNote(filename)
                pageStack.push(editorPage)
            }

            Component.onCompleted: refresh()

            // helper: turn "note-20260705-195335.txt" into "2026-07-05 19:53:35"
            function formatFilename(f) {
                var m = f.match(/note-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.txt/)
                if (m)
                    return m[1] + "-" + m[2] + "-" + m[3] + "  " + m[4] + ":" + m[5] + ":" + m[6]
                return f
            }

            Label {
                anchors.centerIn: parent
                visible: notesPage.notesList.length === 0
                text: i18n.tr("No saved notes yet")
                fontSize: "large"
                color: theme.palette.normal.backgroundTertiaryText
            }

            ListView {
                id: notesListView
                anchors {
                    top: notesHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                clip: true
                model: notesPage.notesList

                delegate: ListItem {
                    height: noteColumn.height + units.gu(2)

                    property string filename: modelData
                    property string noteContent: stt.readNote(filename)

                    onClicked: notesPage.openEditor(filename)

                    Column {
                        id: noteColumn
                        anchors {
                            left: parent.left
                            right: deleteButton.left
                            top: parent.top
                            leftMargin: units.gu(2)
                            rightMargin: units.gu(1)
                            topMargin: units.gu(1)
                        }
                        spacing: units.gu(0.5)

                        Label {
                            text: notesPage.formatFilename(filename)
                            fontSize: "small"
                            color: theme.palette.normal.backgroundTertiaryText
                        }
                        Label {
                            width: parent.width
                            text: noteContent
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    // ---- visible delete button ------------------------
                    AbstractButton {
                        id: deleteButton
                        width: units.gu(5)
                        height: units.gu(5)
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: units.gu(1)
                        }
                        onClicked: {
                            stt.deleteNote(filename)
                            notesPage.refresh()
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5)
                            height: units.gu(2.5)
                            name: "delete"
                            color: theme.palette.normal.negative
                        }
                    }

                    leadingActions: ListItemActions {
                        actions: [
                            Action {
                                iconName: "delete"
                                onTriggered: {
                                    stt.deleteNote(filename)
                                    notesPage.refresh()
                                }
                            }
                        ]
                    }

                    trailingActions: ListItemActions {
                        actions: [
                            Action {
                                iconName: "edit-copy"
                                onTriggered: Clipboard.push(noteContent)
                            }
                        ]
                    }
                }
            }

            onVisibleChanged: {
                if (visible) refresh()
            }
        }

        // ============================================================
        // PAGE 3: Note Editor (type or dictate)
        // ============================================================
        Page {
            id: editorPage
            visible: false

            property string filename: ""

            header: PageHeader {
                id: editorHeader
                title: editorPage.filename
                       ? notesPage.formatFilename(editorPage.filename)
                       : i18n.tr("New note")
                trailingActionBar.actions: [
                    Action {
                        iconName: "delete"
                        text: i18n.tr("Delete")
                        onTriggered: {
                            if (editorPage.filename !== "")
                                stt.deleteNote(editorPage.filename)
                            pageStack.pop()
                            notesPage.refresh()
                        }
                    }
                ]
            }

            // Tap inside to type — the phone keyboard opens automatically
            TextArea {
                id: editorArea
                anchors {
                    top: editorHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: editorToolbar.top
                    margins: units.gu(1)
                }
                autoSize: false
                placeholderText: i18n.tr("Type here, or hold the mic to dictate…")
            }

            // ---- bottom toolbar: save + mic ---------------------------
            Item {
                id: editorToolbar
                height: units.gu(10)
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                Button {
                    text: i18n.tr("Save")
                    color: theme.palette.normal.positive
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: units.gu(2)
                    }
                    onClicked: {
                        var ok
                        if (editorPage.filename === "")
                            ok = stt.saveNote(editorArea.text)   // new note
                        else
                            ok = stt.updateNote(editorPage.filename, editorArea.text)
                        console.log("editor save: filename='" + editorPage.filename
                                    + "' len=" + editorArea.text.length + " ok=" + ok)
                        if (ok) {
                            pageStack.pop()
                            notesPage.refresh()
                        }
                    }
                }

                // hold-to-talk mic, dictation is appended to the text
                Rectangle {
                    id: editorMic
                    width: units.gu(8)
                    height: width
                    radius: width / 2
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: units.gu(2)
                    }
                    color: stt.recording
                           ? theme.palette.normal.negative
                           : stt.busy ? theme.palette.normal.base
                                      : theme.palette.normal.positive
                    scale: editorMicArea.pressed ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    visible: stt.modelReady

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3.5)
                        height: units.gu(3.5)
                        name: "audio-input-microphone-symbolic"
                        color: "white"
                    }

                    MouseArea {
                        id: editorMicArea
                        anchors.fill: parent
                        enabled: !stt.busy
                        onPressed: stt.startRecording()
                        onReleased: stt.stopAndTranscribe()
                        onCanceled: stt.cancelRecording()
                    }
                }

                ActivityIndicator {
                    anchors.centerIn: parent
                    running: stt.busy
                    visible: stt.busy
                }
            }
        }

        // ============================================================
        // PAGE 4: Settings (configuration)
        // ============================================================
        Page {
            id: settingsPage
            visible: false
            header: PageHeader {
                id: settingsHeader
                title: i18n.tr("Settings")
            }

            Column {
                anchors {
                    top: settingsHeader.bottom
                    left: parent.left
                    right: parent.right
                    margins: units.gu(2)
                }
                spacing: units.gu(2)

                Label {
                    text: i18n.tr("Speech recognition model")
                    fontSize: "large"
                }

                OptionSelector {
                    id: modelSelector
                    width: parent.width
                    model: [
                        i18n.tr("Tiny — fastest, 75 MB"),
                        i18n.tr("Base — more accurate, 142 MB")
                    ]
                    selectedIndex: stt.modelName === "ggml-base.en.bin" ? 1 : 0
                    onSelectedIndexChanged: {
                        stt.modelName = selectedIndex === 1 ? "ggml-base.en.bin"
                                                            : "ggml-tiny.en.bin"
                    }
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: stt.modelReady ? theme.palette.normal.positive
                                          : theme.palette.normal.negative
                    text: stt.modelReady
                          ? i18n.tr("Model downloaded and ready")
                          : i18n.tr("This model is not downloaded yet")
                }

                Button {
                    visible: !stt.modelReady
                    width: parent.width
                    color: theme.palette.normal.positive
                    enabled: !stt.downloading
                    text: stt.downloading
                          ? i18n.tr("Downloading… %1%").arg(Math.round(stt.downloadProgress * 100))
                          : i18n.tr("Download model")
                    onClicked: stt.downloadModel()
                }

                ProgressBar {
                    width: parent.width
                    visible: stt.downloading
                    value: stt.downloadProgress
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: theme.palette.normal.backgroundTertiaryText
                    text: i18n.tr("Tiny responds quickest on this phone. Base understands unclear speech better but takes roughly twice as long to transcribe. The model choice is remembered.")
                }

                Rectangle {
                    width: parent.width
                    height: units.dp(1)
                    color: theme.palette.normal.base
                }

                ListItem {
                    height: units.gu(7)
                    onClicked: pageStack.push(helpPage)
                    Row {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: units.gu(1)
                        }
                        spacing: units.gu(2)
                        Icon {
                            name: "help"
                            width: units.gu(3)
                            height: units.gu(3)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: i18n.tr("Instructions")
                            fontSize: "large"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // future configuration entries go here
            }
        }

        // ============================================================
        // PAGE 6: Widget mode ("VoiceNote Button" launcher entry)
        // ============================================================
        Page {
            id: buttonPage
            visible: false

            property string lastResult: ""

            // no header — just the button
            header: Item { visible: false; height: 0 }

            Rectangle {
                anchors.fill: parent
                color: "#101512"
            }

            Column {
                anchors.centerIn: parent
                spacing: units.gu(3)
                width: parent.width - units.gu(4)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(28)
                    height: width
                    radius: width / 2
                    color: stt.recording
                           ? theme.palette.normal.negative
                           : stt.busy ? theme.palette.normal.base
                                      : theme.palette.normal.positive
                    scale: bigArea.pressed ? 1.06 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }

                    Label {
                        anchors.centerIn: parent
                        text: stt.recording ? i18n.tr("Listening")
                              : stt.busy   ? i18n.tr("Working…")
                                           : i18n.tr("Hold to talk")
                        color: "white"
                        fontSize: "x-large"
                    }

                    MouseArea {
                        id: bigArea
                        anchors.fill: parent
                        enabled: !stt.busy && stt.modelReady
                        onPressed: stt.startRecording()
                        onReleased: stt.stopAndTranscribe()
                        onCanceled: stt.cancelRecording()
                    }
                }

                ActivityIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: stt.busy
                    visible: stt.busy
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#a8b5ae"
                    text: buttonPage.lastResult !== ""
                          ? buttonPage.lastResult
                          : stt.modelReady
                            ? i18n.tr("Speak a note or a command — it's handled automatically")
                            : i18n.tr("Open the full VoiceNote app once to download the speech model")
                }
            }
        }

        // ============================================================
        // PAGE 5: Instructions / Help
        // ============================================================
        Page {
            id: helpPage
            visible: false
            header: PageHeader {
                id: helpHeader
                title: i18n.tr("Instructions")
            }

            Flickable {
                anchors {
                    top: helpHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                contentHeight: helpColumn.height + units.gu(4)
                clip: true

                Column {
                    id: helpColumn
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: units.gu(2)
                    }
                    spacing: units.gu(2)

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Dictating notes")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("On the main page, press and HOLD the big button, speak, then release. Your words appear in the text box below — edit them if needed, then tap Save note. Copy puts the text on the clipboard; Clear empties the box.\n\nEverything is processed on the phone. Nothing you say ever leaves the device.")
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Browsing & editing notes")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("Tap the notes icon (top right) to see saved notes.\n\u2022 Tap a note to open it\n\u2022 Tap the red trash icon to delete it\n\u2022 Swipe a note right for copy\n\u2022 Tap + to start a blank note\n\nInside a note: tap the text to type with the keyboard, or hold the round mic button to dictate — the words are added to the end. Tap Save when done.")
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Voice commands")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("Speak these into the main button — they run instantly instead of becoming a note:\n\n\u2022 \"Open camera\" — launches an app. Works with: camera, clock, calculator, calendar, gallery, files, music, weather, terminal, browser, store, maps, signal, mail, youtube, recorder, duolingo, tailscale, trading, codium, phone, messages, contacts, settings\n\n\u2022 \"Search for ubuntu touch news\" — searches the web in the browser")
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Alarms")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("Say \"set alarm\" plus a time. These become real alarms in the Clock app and ring even when VoiceNote is closed.\n\n\u2022 \"Set alarm for tomorrow at 6 AM\"\n\u2022 \"Set alarm for February 14th for Valentine's day at 9 AM\"\n\u2022 \"Set alarm for Monday at 7:30 PM\"\n\u2022 \"Wake me up at 6 AM\"\n\nIf a date already passed this year, the alarm is set for next year. A bare time means the next occurrence.")
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Calendar events")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("Say \"add event\", \"create meeting\", or \"add appointment\" plus what and when. Events appear in the Calendar app, one hour long.\n\n\u2022 \"Add event dentist appointment on February 14th at 9 AM\"\n\u2022 \"Create meeting with John tomorrow at 2 PM\"\n\u2022 \"Add appointment haircut on Friday at 4:30 PM\"\n\nThe words that aren't a date or time become the event title.")
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        fontSize: "large"
                        text: i18n.tr("Speech model")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: i18n.tr("In Settings you can switch between the Tiny model (fastest) and the Base model (more accurate, slower). Each model is downloaded once (~75–142 MB) and then works fully offline.\n\nSpeak clearly and keep the button held the whole time you talk — short clips under half a second are ignored.")
                    }
                }
            }
        }
    }
}

