import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool isTabActive: false
    property var prayerData: null
    property bool isLoading: false
    property bool showingLocationPicker: false

    property string currentProv: "Sulawesi Selatan"
    property string currentCity: "Kota Makassar"
    property bool isAutoDetect: true
    property string bulanNama: ""
    property int tahunVal: 2026
    property var todayItem: null
    property var prayersList: []
    property var nextPrayerItem: null
    property var currentPrayerItem: null

    // Location Picker States
    property var allProvinces: []
    property var allCities: []
    property string pickerProv: ""
    property string pickerCity: ""
    property string provSearchText: ""
    property string citySearchText: ""

    onIsTabActiveChanged: {
        if (isTabActive) {
            recalculateStatus()
            refreshData()
        }
    }

    Component.onCompleted: {
        refreshData()
    }

    function recalculateStatus() {
        if (!root.todayItem) return

        const now = new Date()
        const currentMinutes = now.getHours() * 60 + now.getMinutes()

        const prayerKeys = [
            { id: "subuh", name: "Fajr", icon: "󰖔", time: root.todayItem.subuh || "04:20" },
            { id: "dzuhur", name: "Dhuhr", icon: "󰖨", time: root.todayItem.dzuhur || "11:49" },
            { id: "ashar", name: "Asr", icon: "󰖝", time: root.todayItem.ashar || "15:04" },
            { id: "maghrib", name: "Maghrib", icon: "󰖚", time: root.todayItem.maghrib || "17:58" },
            { id: "isya", name: "Isha", icon: "󰖛", time: root.todayItem.isya || "19:08" }
        ]

        let updatedList = []
        let nextPrayer = null
        let minDiff = 999999
        let lastPrayer = prayerKeys[prayerKeys.length - 1]

        for (let i = 0; i < prayerKeys.length; i++) {
            const p = prayerKeys[i]
            let pMinutes = 0
            if (p.time && p.time.indexOf(":") !== -1) {
                const parts = p.time.split(":")
                pMinutes = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10)
            }
            const diff = pMinutes - currentMinutes
            const isPassed = (diff <= 0)

            if (diff > 0 && diff < minDiff) {
                minDiff = diff
                nextPrayer = {
                    id: p.id,
                    name: p.name,
                    time: p.time,
                    diff_minutes: diff
                }
            }

            if (isPassed) {
                lastPrayer = p
            }

            updatedList.push({
                id: p.id,
                name: p.name,
                icon: p.icon,
                time: p.time,
                passed: isPassed
            })
        }

        if (!nextPrayer) {
            const first = prayerKeys[0]
            let fMinutes = 0
            if (first.time && first.time.indexOf(":") !== -1) {
                const parts = first.time.split(":")
                fMinutes = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10)
            }
            const diff = (24 * 60 - currentMinutes) + fMinutes
            nextPrayer = {
                id: first.id,
                name: first.name + " (Tomorrow)",
                time: first.time,
                diff_minutes: diff
            }
        }

        const hours = Math.floor(nextPrayer.diff_minutes / 60)
        const mins = nextPrayer.diff_minutes % 60
        nextPrayer.countdown = (hours > 0 ? (hours + "h " + mins + "m remaining") : (mins + "m remaining"))

        root.prayersList = updatedList
        root.nextPrayerItem = nextPrayer
        root.currentPrayerItem = lastPrayer
    }

    function refreshData() {
        isLoading = true
        recalculateStatus()
        prayerProc.running = false
        prayerProc.running = true
    }

    function triggerAutoDetect() {
        isLoading = true
        autoDetectProc.running = false
        autoDetectProc.running = true
    }

    function openLocationPicker() {
        showingLocationPicker = true
        pickerProv = currentProv
        pickerCity = currentCity
        provSearchText = ""
        citySearchText = ""
        loadProvinces()
        loadCities(pickerProv)
    }

    function loadProvinces() {
        provincesProc.running = false
        provincesProc.running = true
    }

    function loadCities(prov) {
        if (!prov) return
        citiesProc.command = ["python3", Sys.scriptPath("prayer_service.py"), "--get-cities", prov]
        citiesProc.running = false
        citiesProc.running = true
    }

    function saveManualLocation() {
        if (!pickerProv || !pickerCity) return
        isLoading = true
        setLocationProc.command = ["python3", Sys.scriptPath("prayer_service.py"), "--set-location", pickerProv, pickerCity]
        setLocationProc.running = false
        setLocationProc.running = true
    }

    // Process to get prayer data
    Process {
        id: prayerProc
        command: ["python3", Sys.scriptPath("prayer_service.py"), "--get-data"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                try {
                    const data = JSON.parse(text)
                    if (data.status === "success") {
                        root.prayerData = data
                        root.currentProv = data.provinsi || ""
                        root.currentCity = data.kabkota || ""
                        root.isAutoDetect = data.is_auto ?? true
                        root.bulanNama = data.bulan_nama || ""
                        root.tahunVal = data.tahun || 2026
                        root.todayItem = data.today || null
                        root.recalculateStatus()
                    }
                } catch (e) {}
            }
        }
    }

    // Process for Auto-Detect Location
    Process {
        id: autoDetectProc
        command: ["python3", Sys.scriptPath("prayer_service.py"), "--auto-detect"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                try {
                    const data = JSON.parse(text)
                    if (data.status === "success") {
                        root.prayerData = data
                        root.currentProv = data.provinsi || ""
                        root.currentCity = data.kabkota || ""
                        root.isAutoDetect = true
                        root.todayItem = data.today || null
                        root.recalculateStatus()
                    }
                } catch (e) {}
            }
        }
    }

    // Process to Save Manual Location
    Process {
        id: setLocationProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                root.showingLocationPicker = false
                try {
                    const data = JSON.parse(text)
                    if (data.status === "success") {
                        root.prayerData = data
                        root.currentProv = data.provinsi || ""
                        root.currentCity = data.kabkota || ""
                        root.isAutoDetect = false
                        root.todayItem = data.today || null
                        root.recalculateStatus()
                    }
                } catch (e) {}
            }
        }
    }

    // Process to Fetch Provinces
    Process {
        id: provincesProc
        command: ["python3", Sys.scriptPath("prayer_service.py"), "--get-provinces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.allProvinces = JSON.parse(text) || []
                } catch (e) {}
            }
        }
    }

    // Process to Fetch Cities for selected Province
    Process {
        id: citiesProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.allCities = JSON.parse(text) || []
                } catch (e) {}
            }
        }
    }

    // Live countdown timer while tab is open
    Timer {
        interval: 10000
        running: root.isTabActive
        repeat: true
        onTriggered: root.recalculateStatus()
    }

    // Background refresh timer to handle date change across days
    Timer {
        interval: 900000 // every 15 minutes
        running: true
        repeat: true
        onTriggered: root.refreshData()
    }

    // =========================================================================
    // VIEW 1: MAIN PRAYER SCHEDULE VIEW
    // =========================================================================
    Column {
        anchors.fill: parent
        anchors.topMargin: 4
        spacing: 10
        visible: !root.showingLocationPicker

        // --- ROW 1: LOCATION HEADER & CONTROL ACTIONS ---
        Item {
            width: parent.width
            height: 34

            // Action Buttons on Right
            Row {
                id: actionButtonsRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Auto-Detect Button
                Rectangle {
                    height: 32
                    width: autoRow.implicitWidth + 16
                    radius: 8
                    color: autoMa.containsMouse ? Sys.customModuleHoverBg : (root.isAutoDetect ? Qt.alpha(Theme.accent, 0.20) : Sys.customModuleBg)
                    border.width: 1
                    border.color: root.isAutoDetect ? Theme.accent : Sys.customModuleBorder

                    Row {
                        id: autoRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰑐"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Auto Detect"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: autoMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.triggerAutoDetect()
                    }
                }

                // Set Manual Location Button
                Rectangle {
                    height: 32
                    width: setLocRow.implicitWidth + 16
                    radius: 8
                    color: setLocMa.containsMouse ? Sys.customModuleHoverBg : Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Row {
                        id: setLocRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰒓"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Set Location"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: setLocMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openLocationPicker()
                    }
                }

                // Refresh Button
                Rectangle {
                    height: 32
                    width: 32
                    radius: 8
                    color: refMa.containsMouse ? Sys.customModuleHoverBg : Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Text {
                        anchors.centerIn: parent
                        text: "󰑓"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.fg
                    }

                    MouseArea {
                        id: refMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshData()
                    }
                }
            }

            // Left: Location Chip & Date Badge (Contained within left space - NEVER overlaps!)
            Row {
                anchors.left: parent.left
                anchors.right: actionButtonsRow.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                clip: true

                // Location Pin Chip
                Rectangle {
                    height: 32
                    width: locRow.implicitWidth + 18
                    radius: 8
                    color: Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Row {
                        id: locRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍎"
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: Theme.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.currentCity && root.currentProv) ? (root.currentCity + ", " + root.currentProv) : "Loading Location..."
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }

                        // Auto / Manual Tag
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            width: tagTxt.implicitWidth + 8
                            radius: 5
                            color: root.isAutoDetect ? Qt.alpha(Theme.green, 0.22) : Qt.alpha(Theme.accent, 0.22)

                            Text {
                                id: tagTxt
                                anchors.centerIn: parent
                                text: root.isAutoDetect ? "AUTO" : "MANUAL"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: true
                                color: root.isAutoDetect ? Theme.green : Theme.accent
                            }
                        }
                    }
                }
            }
        }

        // --- ROW 2: HERO BANNER (NEXT PRAYER & COUNTDOWN HIGHLIGHT) ---
        Rectangle {
            id: heroBannerCard
            width: parent.width
            height: 88
            radius: Sys.moduleRadius
            color: Sys.customModuleBg
            border.width: 1
            border.color: Sys.customModuleBorder

            Item {
                anchors.fill: parent
                anchors.margins: 14

                // Left Icon Container (Solid Accent with Base Icon)
                Rectangle {
                    id: heroIconBox
                    width: 54
                    height: 54
                    radius: 14
                    color: Theme.accent
                    border.width: 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: (root.nextPrayerItem && root.nextPrayerItem.id === "subuh") ? "󰖔"
                            : ((root.nextPrayerItem && root.nextPrayerItem.id === "dzuhur") ? "󰖨"
                            : ((root.nextPrayerItem && root.nextPrayerItem.id === "ashar") ? "󰖝"
                            : ((root.nextPrayerItem && root.nextPrayerItem.id === "maghrib") ? "󰖚"
                            : "󰖛")))
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        color: Sys.customBarBg
                    }
                }

                // Center: Next Prayer Title & Time
                Column {
                    anchors.left: heroIconBox.right
                    anchors.leftMargin: 14
                    anchors.right: heroRightCol.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        text: "NEXT PRAYER"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.5
                        color: Qt.alpha(Theme.fg, 0.55)
                    }

                    Row {
                        spacing: 8
                        Text {
                            text: root.nextPrayerItem ? root.nextPrayerItem.name : "—"
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                            color: Theme.fg
                        }

                        Text {
                            text: "•"
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            color: Qt.alpha(Theme.fg, 0.40)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.nextPrayerItem ? root.nextPrayerItem.time : "—"
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                            color: Theme.accent
                        }
                    }
                }

                // Right: Countdown Badge (Solid Accent with Base Text) & Active Prayer Status
                Column {
                    id: heroRightCol
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    spacing: 5

                    Rectangle {
                        height: 28
                        width: cdRow.implicitWidth + 20
                        radius: 8
                        color: Theme.accent
                        border.width: 0
                        anchors.right: parent.right

                        Row {
                            id: cdRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󱎫"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Sys.customBarBg
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.nextPrayerItem ? root.nextPrayerItem.countdown : "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: Sys.customBarBg
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        text: root.currentPrayerItem ? ("Current: " + root.currentPrayerItem.name) : "Kemenag RI"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Qt.alpha(Theme.fg, 0.55)
                    }
                }
            }
        }

        // --- ROW 3: 5 SHALAT FARDHU CARDS (SUBUH, DZUHUR, ASHAR, MAGHRIB, ISYA) ---
        Row {
            width: parent.width
            height: parent.height - 4 - 34 - 10 - 88 - 10 - 2
            spacing: 8

            Repeater {
                model: root.prayersList

                Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isNext: root.nextPrayerItem && (root.nextPrayerItem.id === modelData.id)
                    readonly property bool isPassed: modelData.passed && !isNext

                    width: (parent.width - 32) / 5
                    height: parent.height
                    radius: Sys.moduleRadius
                    color: isNext ? Qt.alpha(Theme.accent, 0.20) : Sys.customModuleBg
                    border.width: isNext ? 1.5 : 1
                    border.color: isNext ? Theme.accent : Sys.customModuleBorder

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // Card Content
                    Item {
                        anchors.fill: parent
                        anchors.margins: 10

                        // Top: Icon and Prayer Name (Clean vertical layout - NO overlap!)
                        Column {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 38
                                height: 38
                                radius: 11
                                color: isNext ? Qt.alpha(Theme.accent, 0.28) : (isPassed ? Qt.alpha(Theme.fg, 0.05) : Qt.alpha(Theme.accent, 0.14))

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 19
                                    color: isNext ? Theme.accent : (isPassed ? Qt.alpha(Theme.fg, 0.45) : Theme.accent)
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                color: isNext ? Theme.accent : (isPassed ? Qt.alpha(Theme.fg, 0.70) : Theme.fg)
                            }
                        }

                        // Middle: Large Time
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 12
                            text: modelData.time
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            font.bold: true
                            color: isNext ? Theme.fg : (isPassed ? Qt.alpha(Theme.fg, 0.55) : Theme.fg)
                        }

                        // Bottom: Status Tag (NEXT pill, Completed, or Obligatory Prayer)
                        Item {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: 22

                            // NEXT Badge
                            Rectangle {
                                visible: isNext
                                anchors.centerIn: parent
                                height: 20
                                width: nextTxt.implicitWidth + 14
                                radius: 6
                                color: Theme.accent

                                Text {
                                    id: nextTxt
                                    anchors.centerIn: parent
                                    text: "NEXT"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Sys.customBarBg
                                }
                            }

                            // Passed / Completed Badge
                            Row {
                                visible: isPassed
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰄬"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Qt.alpha(Theme.fg, 0.40)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Completed"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Qt.alpha(Theme.fg, 0.40)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Default: Obligatory Prayer
                            Text {
                                visible: !isNext && !isPassed
                                anchors.centerIn: parent
                                text: "Obligatory Prayer"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Qt.alpha(Theme.fg, 0.40)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // VIEW 2: MANUAL LOCATION SELECTION DRAWER
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        radius: Sys.moduleRadius
        color: Sys.customBarBg
        border.width: 1
        border.color: Sys.customModuleBorder
        visible: root.showingLocationPicker

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header Row
            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰒓"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        color: Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Select Prayer Location (Kemenag RI)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.fg
                    }
                }

                // Close Button
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 7
                    color: closeLocMa.containsMouse ? Sys.customModuleHoverBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.fg
                    }

                    MouseArea {
                        id: closeLocMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showingLocationPicker = false
                    }
                }
            }

            // Two Columns: Left = Provinsi, Right = Kabupaten / Kota
            Row {
                width: parent.width
                height: parent.height - 28 - 42 - 20
                spacing: 12

                // Column 1: Provinsi
                Rectangle {
                    width: (parent.width - 12) / 2
                    height: parent.height
                    radius: 8
                    color: Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: "1. Select Province"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.accent
                        }

                        // Search Input Provinsi
                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: 6
                            color: Theme.bg
                            border.width: 1
                            border.color: provInput.activeFocus ? Theme.accent : Sys.customModuleBorder

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰍉"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Qt.alpha(Theme.fg, 0.40)
                                }

                                TextInput {
                                    id: provInput
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    text: root.provSearchText
                                    onTextChanged: root.provSearchText = text

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Search Province..."
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Qt.alpha(Theme.fg, 0.35)
                                        visible: !provInput.text
                                    }
                                }
                            }
                        }

                        // Scrollable List of Provinces
                        ListView {
                            id: provListView
                            width: parent.width
                            height: parent.height - 30 - 24 - 16
                            clip: true
                            model: {
                                const q = root.provSearchText.toLowerCase().trim()
                                if (!q) return root.allProvinces
                                return root.allProvinces.filter(p => p.toLowerCase().includes(q))
                            }

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: provListView.width
                                height: 28
                                radius: 5
                                color: (root.pickerProv === modelData) ? Qt.alpha(Theme.accent, 0.25) : (pMa.containsMouse ? Sys.customModuleHoverBg : "transparent")

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.pickerProv === modelData
                                    color: (root.pickerProv === modelData) ? Theme.accent : Theme.fg
                                }

                                MouseArea {
                                    id: pMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.pickerProv = modelData
                                        root.loadCities(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Column 2: Kabupaten / Kota
                Rectangle {
                    width: (parent.width - 12) / 2
                    height: parent.height
                    radius: 8
                    color: Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: "2. Select City / Regency"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.accent
                        }

                        // Search Input Kota
                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: 6
                            color: Theme.bg
                            border.width: 1
                            border.color: cityInput.activeFocus ? Theme.accent : Sys.customModuleBorder

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰍉"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Qt.alpha(Theme.fg, 0.40)
                                }

                                TextInput {
                                    id: cityInput
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    text: root.citySearchText
                                    onTextChanged: root.citySearchText = text

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Search City / Regency..."
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Qt.alpha(Theme.fg, 0.35)
                                        visible: !cityInput.text
                                    }
                                }
                            }
                        }

                        // Scrollable List of Cities
                        ListView {
                            id: cityListView
                            width: parent.width
                            height: parent.height - 30 - 24 - 16
                            clip: true
                            model: {
                                const q = root.citySearchText.toLowerCase().trim()
                                if (!q) return root.allCities
                                return root.allCities.filter(c => c.toLowerCase().includes(q))
                            }

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: cityListView.width
                                height: 28
                                radius: 5
                                color: (root.pickerCity === modelData) ? Qt.alpha(Theme.accent, 0.25) : (cMa.containsMouse ? Sys.customModuleHoverBg : "transparent")

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: modelData
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: root.pickerCity === modelData
                                    color: (root.pickerCity === modelData) ? Theme.accent : Theme.fg
                                }

                                MouseArea {
                                    id: cMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.pickerCity = modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Buttons Row: Save and Cancel
            Row {
                anchors.right: parent.right
                spacing: 10

                Rectangle {
                    height: 36
                    width: 100
                    radius: Sys.moduleRadius
                    color: cancelPickMa.containsMouse ? Sys.customModuleHoverBg : Sys.customModuleBg
                    border.width: 1
                    border.color: Sys.customModuleBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: cancelPickMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showingLocationPicker = false
                    }
                }

                Rectangle {
                    height: 36
                    width: 150
                    radius: Sys.moduleRadius
                    color: savePickMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    opacity: (root.pickerProv && root.pickerCity) ? 1.0 : 0.6

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰄬"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Sys.customBarBg
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Apply Location"
                            color: Sys.customBarBg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: savePickMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.pickerProv !== "" && root.pickerCity !== ""
                        onClicked: root.saveManualLocation()
                    }
                }
            }
        }
    }
}
