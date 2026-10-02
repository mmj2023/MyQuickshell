import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

PopupWindow {
    id: root

    property var barWindow: null
    property real anchorX: 0
    property real anchorY: 0
    property date today: new Date()
    property int shownYear: today.getFullYear()
    property int shownMonth: today.getMonth()
    property date selectedDate: today
    property bool showMementoMori: false
    property bool editingLifeProgress: false
    property string lifeProgressError: ""
    property bool editingEvent: false
    property string eventTitle: ""
    property string pomodoroMode: "Work"
    property int pomodoroRemaining: SettingsData.pomodoroWorkMinutes * 60
    property bool pomodoroRunning: false
    property bool celebrationRunning: false
    property int celebrationElapsed: 0
    readonly property var calendarDays: makeCalendarDays()

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function makeCalendarDays() {
        const first = new Date(shownYear, shownMonth, 1);
        const localeFirstDay = Qt.locale().firstDayOfWeek;
        const weekStart = localeFirstDay === 7 ? 0 : localeFirstDay;
        const offset = (first.getDay() - weekStart + 7) % 7;
        const start = new Date(shownYear, shownMonth, 1 - offset);
        const days = [];
        for (let i = 0; i < 42; i++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            days.push({
                "date": day,
                "number": day.getDate(),
                "inMonth": day.getMonth() === shownMonth,
                "isToday": sameDay(day, today),
                "isSelected": sameDay(day, selectedDate)
            });
        }
        return days;
    }

    function shiftMonth(amount) {
        const next = new Date(shownYear, shownMonth + amount, 1);
        shownYear = next.getFullYear();
        shownMonth = next.getMonth();
    }

    function dateKey(date) {
        return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
    }

    function eventsForSelectedDate() {
        return SettingsData.calendarEvents.filter(function(event) {
            return event.date === dateKey(selectedDate);
        });
    }

    function addEvent() {
        const title = eventTitle.trim();
        if (!title)
            return ;

        const events = SettingsData.calendarEvents.slice();
        events.push({
            "id": String(Date.now()) + "-" + String(Math.floor(Math.random() * 1e+06)),
            "date": dateKey(selectedDate),
            "title": title
        });
        SettingsData.set("calendarEvents", events);
        eventTitle = "";
        editingEvent = false;
    }

    function removeEvent(eventId) {
        SettingsData.set("calendarEvents", SettingsData.calendarEvents.filter(function(event) {
            return event.id !== eventId;
        }));
    }

    function resetLifeProgress() {
        SettingsData.set("calendarBirthYear", 0);
        SettingsData.set("calendarLifeExpectancy", 90);
        editingLifeProgress = false;
        lifeProgressError = "";
    }

    function formatPomodoroTime() {
        return String(Math.floor(pomodoroRemaining / 60)).padStart(2, "0") + ":" + String(pomodoroRemaining % 60).padStart(2, "0");
    }

    function switchPomodoroMode() {
        pomodoroMode = pomodoroMode === "Work" ? "Break" : "Work";
        pomodoroRemaining = (pomodoroMode === "Work" ? SettingsData.pomodoroWorkMinutes : SettingsData.pomodoroBreakMinutes) * 60;
        celebrationElapsed = 0;
        celebrationRunning = true;
        celebrationTimer.restart();
        completionSound.running = true;
    }

    function setPomodoroDuration(mode, text) {
        const minutes = Number(text);
        if (!Number.isInteger(minutes) || minutes < 1 || minutes > 180) {
            if (mode === "Work")
                workMinutesInput.text = String(SettingsData.pomodoroWorkMinutes);
            else
                breakMinutesInput.text = String(SettingsData.pomodoroBreakMinutes);
            return ;
        }
        const key = mode === "Work" ? "pomodoroWorkMinutes" : "pomodoroBreakMinutes";
        SettingsData.set(key, minutes);
        if (!pomodoroRunning && pomodoroMode === mode)
            pomodoroRemaining = minutes * 60;

    }

    function toggle(ax, ay) {
        anchorX = ax;
        anchorY = ay;
        visible = !visible;
    }

    function saveLifeProgress() {
        const birthYear = Number(birthYearInput.text);
        const expectancy = Number(lifeExpectancyInput.text);
        if (!Number.isInteger(birthYear) || birthYear < 1900 || birthYear > today.getFullYear()) {
            lifeProgressError = qsTr("Enter a valid birth year.");
            return ;
        }
        if (!Number.isInteger(expectancy) || expectancy < 1 || expectancy > 150) {
            lifeProgressError = qsTr("Life expectancy must be between 1 and 150.");
            return ;
        }
        SettingsData.set("calendarBirthYear", birthYear);
        SettingsData.set("calendarLifeExpectancy", expectancy);
        editingLifeProgress = false;
        lifeProgressError = "";
    }

    function progressForYear() {
        const start = new Date(today.getFullYear(), 0, 1).getTime();
        const end = new Date(today.getFullYear() + 1, 0, 1).getTime();
        return Math.max(0, Math.min(1, (today.getTime() - start) / (end - start)));
    }

    function progressForLife() {
        const birthYear = SettingsData.calendarBirthYear;
        const expectancy = SettingsData.calendarLifeExpectancy;
        if (birthYear < 1900 || birthYear > today.getFullYear() || expectancy < 1)
            return 0;

        const age = (today.getTime() - new Date(birthYear, 0, 1).getTime()) / (365.243 * 24 * 60 * 60 * 1000);
        return Math.max(0, Math.min(1, age / expectancy));
    }

    implicitWidth: 1010
    implicitHeight: 650
    color: "transparent"
    anchor.window: barWindow
    anchor.rect.x: Math.max(8, Math.min((barWindow ? barWindow.width : Screen.width) - implicitWidth - 8, anchorX - implicitWidth / 2))
    anchor.rect.y: anchorY + 4
    visible: false
    grabFocus: true
    surfaceFormat.opaque: false

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: {
            root.today = new Date();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius + 5
        color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, typeof SettingsData !== "undefined" ? SettingsData.popupTransparency : 0.6)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.35)

        Row {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Column {
                width: (parent.width - parent.spacing) * 0.5
                height: parent.height
                spacing: 14

                Row {
                    width: parent.width
                    height: 112
                    spacing: 12

                    Rectangle {
                        width: SettingsData.weatherEnabled ? (parent.width - parent.spacing) * 0.56 : parent.width
                        height: parent.height
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.primaryContainer, 0.78)

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: ClockService.timeString
                                color: Theme.widgetTextColor
                                font.family: Theme.monoFontFamily
                                font.pixelSize: 48
                                font.weight: Font.Bold
                            }

                            Text {
                                text: Qt.locale().dayName(root.today.getDay() === 0 ? 7 : root.today.getDay(), Locale.LongFormat) + ", " + Qt.locale().monthName(root.today.getMonth() + 1, Locale.LongFormat) + " " + root.today.getDate()
                                color: Theme.widgetTextColor
                                font.pixelSize: 13
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.showMementoMori)
                                    root.resetLifeProgress();

                                root.showMementoMori = !root.showMementoMori;
                                root.editingLifeProgress = false;
                                root.lifeProgressError = "";
                            }
                        }

                    }

                    Rectangle {
                        width: SettingsData.weatherEnabled ? (parent.width - parent.spacing) * 0.44 : 0
                        height: parent.height
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.secondaryContainer, 0.78)
                        visible: SettingsData.weatherEnabled

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            DmsIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: WeatherService.weatherIcon(WeatherService.weather.wCode, WeatherService.weather.isDay)
                                size: 34
                                color: Theme.primary
                            }

                            Column {
                                width: parent.width - 42
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    text: WeatherService.currentTempText()
                                    color: Theme.widgetTextColor
                                    font.family: Theme.monoFontFamily
                                    font.pixelSize: 23
                                    font.weight: Font.Medium
                                }

                                Text {
                                    width: parent.width
                                    text: WeatherService.weather.available ? WeatherService.weatherCondition(WeatherService.weather.wCode) : qsTr("Weather unavailable")
                                    color: Theme.widgetTextColor
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: WeatherService.weather.city || ""
                                    color: Theme.widgetInactiveIconColor
                                    font.pixelSize: 10
                                    visible: text.length > 0
                                    elide: Text.ElideRight
                                }

                            }

                        }

                    }

                }

                Row {
                    width: parent.width
                    height: 32
                    spacing: 8

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: previousMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                        DmsIcon {
                            anchors.centerIn: parent
                            name: "chevron_left"
                            color: Theme.widgetInactiveIconColor
                            size: 19
                        }

                        MouseArea {
                            id: previousMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shiftMonth(-1)
                        }

                    }

                    Text {
                        width: parent.width - 128
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().monthName(root.shownMonth + 1, Locale.LongFormat) + " " + root.shownYear
                        color: Theme.widgetTextColor
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: todayMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                        DmsIcon {
                            anchors.centerIn: parent
                            name: "today"
                            size: 17
                            color: Theme.widgetInactiveIconColor
                        }

                        MouseArea {
                            id: todayMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.today = new Date();
                                root.selectedDate = root.today;
                                root.shownYear = root.today.getFullYear();
                                root.shownMonth = root.today.getMonth();
                            }
                        }

                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: nextMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                        DmsIcon {
                            anchors.centerIn: parent
                            name: "chevron_right"
                            color: Theme.widgetInactiveIconColor
                            size: 19
                        }

                        MouseArea {
                            id: nextMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shiftMonth(1)
                        }

                    }

                }

                Grid {
                    width: parent.width
                    columns: 7
                    rowSpacing: 3
                    columnSpacing: 3

                    Repeater {
                        model: 7

                        Text {
                            required property int index

                            width: (parent.width - parent.columnSpacing * 6) / 7
                            height: 22
                            text: {
                                const firstDay = Qt.locale().firstDayOfWeek;
                                const start = firstDay === 7 ? 0 : firstDay;
                                return Qt.locale().dayName((start + index + 6) % 7 + 1, Locale.NarrowFormat);
                            }
                            color: Theme.widgetInactiveIconColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                    }

                    Repeater {
                        model: root.calendarDays

                        delegate: Rectangle {
                            required property var modelData

                            width: (parent.width - parent.columnSpacing * 6) / 7
                            height: 36
                            radius: Theme.cornerRadius
                            color: modelData.isSelected ? Theme.primary : modelData.inMonth ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.58) : "transparent"
                            border.width: modelData.isToday && !modelData.isSelected ? 1 : 0
                            border.color: Theme.primary
                            opacity: modelData.inMonth ? 1 : 0.38

                            Text {
                                anchors.centerIn: parent
                                text: modelData.number
                                color: modelData.isSelected ? Theme.onPrimary : modelData.inMonth ? Theme.widgetTextColor : Theme.widgetInactiveIconColor
                                font.pixelSize: 13
                                font.weight: modelData.isToday || modelData.isSelected ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function(mouse) {
                                    root.selectedDate = modelData.date;
                                    if (mouse.button === Qt.RightButton) {
                                        root.editingEvent = true;
                                        root.eventTitle = "";
                                    } else if (!modelData.inMonth) {
                                        root.shownMonth = modelData.date.getMonth();
                                        root.shownYear = modelData.date.getFullYear();
                                    }
                                }
                            }

                        }

                    }

                }

                Column {
                    width: parent.width
                    spacing: 9

                    Row {
                        width: parent.width
                        spacing: 9
                        visible: true

                        Text {
                            width: 88
                            height: 28
                            text: root.shownYear
                            color: Theme.widgetInactiveIconColor
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            width: parent.width - 150
                            height: 28
                            color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 8
                                radius: 4
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    width: parent.width * root.progressForYear()
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.primary
                                }

                            }

                        }

                        Text {
                            width: 44
                            height: 28
                            text: Math.round(root.progressForYear() * 100) + "%"
                            color: Theme.widgetInactiveIconColor
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }

                    }

                    Row {
                        width: parent.width
                        spacing: 9
                        visible: root.showMementoMori && SettingsData.calendarBirthYear > 0 && !root.editingLifeProgress

                        Text {
                            width: 88
                            height: 28
                            text: SettingsData.calendarBirthYear + " →"
                            color: Theme.widgetInactiveIconColor
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            width: parent.width - 150
                            height: 28
                            color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 8
                                radius: 4
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    width: parent.width * root.progressForLife()
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.tertiary
                                }

                            }

                        }

                        Text {
                            width: 44
                            height: 28
                            text: Math.round(root.progressForLife() * 100) + "%"
                            color: Theme.widgetInactiveIconColor
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }

                    }

                    Row {
                        width: parent.width
                        spacing: 9
                        visible: root.showMementoMori && (root.editingLifeProgress || SettingsData.calendarBirthYear === 0)

                        Text {
                            width: 88
                            height: 34
                            text: qsTr("Memento mori")
                            color: Theme.widgetInactiveIconColor
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        TextField {
                            id: birthYearInput

                            width: 104
                            height: 34
                            placeholderText: qsTr("Birth year")
                            text: SettingsData.calendarBirthYear > 0 ? String(SettingsData.calendarBirthYear) : ""
                            color: Theme.widgetTextColor
                            placeholderTextColor: Theme.widgetInactiveIconColor
                            leftPadding: 9
                            rightPadding: 9
                            font.pixelSize: 12

                            background: Rectangle {
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                                border.width: birthYearInput.activeFocus ? 1 : 0
                                border.color: Theme.primary
                            }

                            validator: IntValidator {
                                bottom: 1900
                                top: root.today.getFullYear()
                            }

                        }

                        TextField {
                            id: lifeExpectancyInput

                            width: 78
                            height: 34
                            placeholderText: qsTr("Years")
                            text: String(SettingsData.calendarLifeExpectancy)
                            color: Theme.widgetTextColor
                            placeholderTextColor: Theme.widgetInactiveIconColor
                            leftPadding: 9
                            rightPadding: 9
                            font.pixelSize: 12

                            background: Rectangle {
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                                border.width: lifeExpectancyInput.activeFocus ? 1 : 0
                                border.color: Theme.primary
                            }

                            validator: IntValidator {
                                bottom: 1
                                top: 150
                            }

                        }

                        Rectangle {
                            width: 48
                            height: 34
                            radius: Theme.cornerRadius
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("Save")
                                color: Theme.onPrimary
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.saveLifeProgress()
                            }

                        }

                    }

                    Text {
                        text: root.lifeProgressError
                        color: Theme.error
                        font.pixelSize: 11
                        visible: root.showMementoMori && root.editingLifeProgress && text.length > 0
                    }

                }

            }

            Rectangle {
                width: (parent.width - parent.spacing) * 0.5
                height: parent.height
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.widgetBaseBackgroundColor, 0.72)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.2)

                Column {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 12

                    Row {
                        width: parent.width
                        height: 28
                        spacing: 8

                        DmsIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "event"
                            size: 19
                            color: Theme.primary
                        }

                        Text {
                            width: parent.width - 70
                            height: parent.height
                            text: qsTr("Events")
                            color: Theme.widgetTextColor
                            font.pixelSize: 17
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: 32
                            height: 28
                            radius: Theme.cornerRadius
                            color: addEventMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.18) : "transparent"

                            DmsIcon {
                                anchors.centerIn: parent
                                name: "add"
                                size: 19
                                color: Theme.primary
                            }

                            MouseArea {
                                id: addEventMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.eventTitle = "";
                                    root.editingEvent = !root.editingEvent;
                                }
                            }

                        }

                    }

                    Item {
                        width: parent.width
                        height: parent.height - 150

                        Flickable {
                            id: eventFlickable

                            anchors.fill: parent
                            contentHeight: eventColumn.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: eventColumn

                                width: parent.width
                                height: root.eventsForSelectedDate().length === 0 && !root.editingEvent ? eventFlickable.height : implicitHeight
                                spacing: 8

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    visible: root.editingEvent

                                    TextField {
                                        width: parent.width - 84
                                        height: 38
                                        placeholderText: qsTr("Event for ") + root.dateKey(root.selectedDate)
                                        text: root.eventTitle
                                        color: Theme.widgetTextColor
                                        placeholderTextColor: Theme.widgetInactiveIconColor
                                        leftPadding: 10
                                        font.pixelSize: 13
                                        onTextChanged: root.eventTitle = text
                                        onAccepted: root.addEvent()

                                        background: Rectangle {
                                            radius: Theme.cornerRadius
                                            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                                            border.width: parent.activeFocus ? 1 : 0
                                            border.color: Theme.primary
                                        }

                                    }

                                    Rectangle {
                                        width: 76
                                        height: 38
                                        radius: Theme.cornerRadius
                                        color: Theme.primary

                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("Add")
                                            color: Theme.onPrimary
                                            font.pixelSize: 13
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.addEvent()
                                        }

                                    }

                                }

                                Repeater {
                                    model: root.eventsForSelectedDate()

                                    delegate: Rectangle {
                                        required property var modelData

                                        width: eventColumn.width
                                        height: 44
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.68)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Text {
                                                width: parent.width - 42
                                                height: parent.height
                                                text: modelData.title
                                                color: Theme.widgetTextColor
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            Rectangle {
                                                width: 32
                                                height: 32
                                                anchors.verticalCenter: parent.verticalCenter
                                                radius: 16
                                                color: deleteMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.2) : "transparent"

                                                DmsIcon {
                                                    anchors.centerIn: parent
                                                    name: "delete_outline"
                                                    color: Theme.error
                                                    size: 18
                                                }

                                                MouseArea {
                                                    id: deleteMouse

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onClicked: root.removeEvent(modelData.id)
                                                }

                                            }

                                        }

                                    }

                                }

                                Column {
                                    width: parent.width
                                    height: parent.height
                                    visible: root.eventsForSelectedDate().length === 0 && !root.editingEvent

                                    Item {
                                        anchors.fill: parent

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 12

                                            DmsIcon {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                name: "emoji_events"
                                                size: 48
                                                color: Theme.withAlpha(Theme.primary, 0.85)
                                            }

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: qsTr("You're all caught up")
                                                color: Theme.widgetTextColor
                                                font.pixelSize: 18
                                            }

                                            Text {
                                                width: eventColumn.width - 24
                                                text: qsTr("No events for this day")
                                                color: Theme.widgetInactiveIconColor
                                                font.pixelSize: 14
                                                horizontalAlignment: Text.AlignHCenter
                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.25)
                    }

                    Row {
                        width: parent.width
                        height: 76
                        spacing: 12

                        Column {
                            width: 78
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: qsTr("Pomodoro")
                                color: Theme.widgetTextColor
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Text {
                                text: root.pomodoroMode
                                color: Theme.widgetInactiveIconColor
                                font.pixelSize: 11
                            }

                        }

                        Text {
                            width: 72
                            height: parent.height
                            text: root.formatPomodoroTime()
                            color: Theme.widgetTextColor
                            font.family: Theme.monoFontFamily
                            font.pixelSize: 25
                            verticalAlignment: Text.AlignVCenter
                        }

                        Column {
                            width: 58
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: qsTr("Work (min)")
                                color: Theme.widgetInactiveIconColor
                                font.pixelSize: 10
                            }

                            TextField {
                                id: workMinutesInput

                                width: 58
                                height: 32
                                text: String(SettingsData.pomodoroWorkMinutes)
                                color: Theme.widgetTextColor
                                horizontalAlignment: TextInput.AlignHCenter
                                font.pixelSize: 12
                                selectByMouse: true
                                onEditingFinished: root.setPomodoroDuration("Work", text)

                                validator: IntValidator {
                                    bottom: 1
                                    top: 180
                                }

                                background: Rectangle {
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.9)
                                    border.width: workMinutesInput.activeFocus ? 1 : 0
                                    border.color: Theme.primary
                                }

                            }

                        }

                        Column {
                            width: 58
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: qsTr("Break (min)")
                                color: Theme.widgetInactiveIconColor
                                font.pixelSize: 10
                            }

                            TextField {
                                id: breakMinutesInput

                                width: 58
                                height: 32
                                text: String(SettingsData.pomodoroBreakMinutes)
                                color: Theme.widgetTextColor
                                horizontalAlignment: TextInput.AlignHCenter
                                font.pixelSize: 12
                                selectByMouse: true
                                onEditingFinished: root.setPomodoroDuration("Break", text)

                                validator: IntValidator {
                                    bottom: 1
                                    top: 180
                                }

                                background: Rectangle {
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.9)
                                    border.width: breakMinutesInput.activeFocus ? 1 : 0
                                    border.color: Theme.primary
                                }

                            }

                        }

                        Rectangle {
                            width: 70
                            height: 36
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.cornerRadius
                            color: Theme.primary

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                DmsIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: root.pomodoroRunning ? "pause" : "play_arrow"
                                    color: Theme.onPrimary
                                    size: 17
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.pomodoroRunning ? qsTr("Pause") : qsTr("Start")
                                    color: Theme.onPrimary
                                    font.pixelSize: 12
                                }

                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.pomodoroRunning = !root.pomodoroRunning
                            }

                        }

                        Rectangle {
                            width: 36
                            height: 36
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.8)

                            DmsIcon {
                                anchors.centerIn: parent
                                name: "restart_alt"
                                color: Theme.widgetTextColor
                                size: 18
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.pomodoroRunning = false;
                                    root.pomodoroMode = "Work";
                                    root.pomodoroRemaining = SettingsData.pomodoroWorkMinutes * 60;
                                    root.celebrationRunning = false;
                                }
                            }

                        }

                    }

                }

            }

        }

        Canvas {
            id: confettiCanvas

            anchors.fill: parent
            z: 10
            visible: root.celebrationRunning
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const colors = [Theme.primary, Theme.tertiary, Theme.secondary, Theme.error];
                for (let i = 0; i < 54; i++) {
                    const seed = i * 0.618034;
                    const xStart = width * (0.12 + (seed % 0.76));
                    const drift = Math.sin(seed * 21 + root.celebrationElapsed / 260) * 24;
                    const seconds = root.celebrationElapsed / 1000;
                    const x = xStart + drift;
                    const y = -24 + seconds * (75 + (i % 7) * 16) + seconds * seconds * 28;
                    if (y < height + 12) {
                        ctx.save();
                        ctx.translate(x, y);
                        ctx.rotate(seconds * (i % 2 === 0 ? 3 : -3) + seed * 5);
                        ctx.fillStyle = colors[i % colors.length];
                        ctx.globalAlpha = Math.max(0, 1 - root.celebrationElapsed / 4500);
                        ctx.fillRect(-4, -7, 8, 14);
                        ctx.restore();
                    }
                }
            }
        }

        Timer {
            id: celebrationTimer

            interval: 32
            repeat: true
            running: root.celebrationRunning
            onTriggered: {
                root.celebrationElapsed += interval;
                confettiCanvas.requestPaint();
                if (root.celebrationElapsed >= 4500)
                    root.celebrationRunning = false;

            }
        }

        Process {
            id: completionSound

            command: ["canberra-gtk-play", "-i", "complete"]
            onExited: function(status, exitStatus) {
                if (status !== 0)
                    console.warn("Pomodoro completion sound failed with status " + exitStatus);

            }
        }

        Timer {
            interval: 1000
            repeat: true
            running: root.pomodoroRunning
            onTriggered: {
                if (root.pomodoroRemaining > 1) {
                    root.pomodoroRemaining--;
                } else {
                    root.pomodoroRemaining = 0;
                    root.pomodoroRunning = false;
                    root.switchPomodoroMode();
                }
            }
        }

    }

}
