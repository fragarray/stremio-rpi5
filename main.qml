import QtQuick 2.7
import QtWebEngine 1.4
import QtWebChannel 1.0
import QtQuick.Window 2.2 // for Window instead of ApplicationWindow; also for Screen
import QtQuick.Controls 1.4 // for ApplicationWindow
import QtQuick.Dialogs 1.2
import com.stremio.process 1.0
import com.stremio.screensaver 1.0
import com.stremio.libmpv 1.0
import com.stremio.clipboard 1.0
import QtQml 2.2
import Qt.labs.settings 1.0

import "autoupdater.js" as Autoupdater

ApplicationWindow {
    id: root
    visible: true

    minimumWidth: 1000
    minimumHeight: 650

    readonly property int initialWidth: Math.max(root.minimumWidth, Math.min(1600, Screen.desktopAvailableWidth * 0.8))
    readonly property int initialHeight: Math.max(root.minimumHeight, Math.min(1000, Screen.desktopAvailableHeight * 0.8))

    width: root.initialWidth
    height: root.initialHeight

    property bool quitting: false

    color: "#0c0b11";
    title: appTitle

    property var previousVisibility: Window.Windowed
    property bool wasFullScreen: false

    function setFullScreen(fullscreen) {
        if (fullscreen) {
            root.visibility = Window.FullScreen;
            root.wasFullScreen = true;
        } else {
            root.visibility = root.previousVisibility;
            root.wasFullScreen = false;
        }
    }

    function showWindow() {
            if (root.wasFullScreen) {
                root.visibility = Window.FullScreen;
            } else {
                root.visibility = root.previousVisibility;
            }
            root.raise();
            root.requestActivate();
    }

    function updatePreviousVisibility() {
        if (root.visible && root.visibility != Window.FullScreen && root.visibility != Window.Minimized) {
            root.previousVisibility = root.visibility;
        }
    }

    // Transport
    QtObject {
        id: transport
        readonly property string shellVersion: Qt.application.version
        property string serverAddress: "http://127.0.0.1:11470" // will be set to something else if server inits on another port
        
        readonly property bool isFullscreen: root.visibility === Window.FullScreen // just to send the initial state

        // Dual subtitles state
        property string dualSecondarySubUrl: ""
        property int dualSecondaryTrackId: -1
        property bool dualSubtitlesActive: false
        property var dualSecondaryStyle: null
        property string dualContentType: ""   // e.g. "series" or "movie"
        property string dualVideoId: ""        // e.g. "tt32420734:1:2"
        property bool dualPlayerMode: false     // true when player UI is active
        property int dualPrimaryTrackId: -1
        property string dualPrimarySubUrl: ""
        property bool dualPrimaryManaged: false  // true when primary is rendered via mpv (after lang change)

        signal event(var ev, var args)
        function onEvent(ev, args) {
            // Debug: log ALL events from web UI
            if (ev !== "mpv-prop-change" && ev !== "mpv-observe-prop") {
                try {
                    console.log("[DualSub-transport] ev=" + ev + " args=" + JSON.stringify(args));
                } catch(e) {
                    console.log("[DualSub-transport] ev=" + ev + " args=(not serializable)");
                }
            }

            if (ev === "quit") quitApp()
            if (ev === "app-ready") transport.flushQueue()

            // Cleanup dual when user switches to an embedded subtitle via sid
            // (sid="no" is normal for addon subs rendered by HTML overlay, so ignore it)
            // Also skip cleanup if primary is managed by mpv (we set sid ourselves)
            if (ev === "mpv-set-prop" && args && args[0] === "sid" && transport.dualSubtitlesActive && !transport.dualPrimaryManaged) {
                if (args[1] !== "no" && args[1] !== false) {
                    console.log("[DualSub] sid changed to '" + args[1] + "' while dual active, cleaning up");
                    mpv.cleanupDualSub();
                }
            }

            if (ev === "mpv-command" && args && args[0] !== "run") mpv.command(args)
            if (ev === "mpv-set-prop") {
                // Block sub-ass-override from web UI when dual subtitles active
                // (web UI sends no-sub-ass/sub-ass-override that breaks our ASS font styling)
                if (transport.dualSubtitlesActive &&
                    (args[0] === "sub-ass-override" || args[0] === "no-sub-ass" ||
                     args[0] === "secondary-sub-ass-override")) {
                    console.log("[DualSub] Blocked web UI override: " + args[0] + "=" + args[1]);
                } else {
                    mpv.setProperty(args[0], args[1]);
                }
                if (args[0] === "pause") {
                    shouldDisableScreensaver(!args[1]);
                }
            }
            if (ev === "mpv-observe-prop") mpv.observeProperty(args)

            // Dual subtitles: enable (manual event from web UI, if ever used)
            if (ev === "dual-sub-enable" && args) {
                transport.dualSecondarySubUrl = args.secondaryUrl || "";
                transport.dualSecondaryStyle = args.style || null;
                transport.dualSubtitlesActive = true;
                mpv.command(["sub-add", args.secondaryUrl, "auto", "DualSecondary"]);
                console.log("[DualSub] Enabled dual subtitles, loading secondary: " + args.secondaryUrl);
            }

            // Dual subtitles: disable
            if (ev === "dual-sub-disable") {
                mpv.setProperty("secondary-sid", "no");
                if (transport.dualSecondaryTrackId > 0) {
                    mpv.command(["sub-remove", transport.dualSecondaryTrackId.toString()]);
                }
                transport.dualSubtitlesActive = false;
                transport.dualSecondarySubUrl = "";
                transport.dualSecondaryTrackId = -1;
                transport.dualSecondaryStyle = null;
                console.log("[DualSub] Disabled dual subtitles");
            }

            // Dual subtitles: independent delay for secondary
            if (ev === "secondary-sub-delay") {
                mpv.setProperty("secondary-sub-delay", args);
            }

            // Dual subtitles: toggle secondary visibility
            if (ev === "secondary-sub-toggle") {
                mpv.setProperty("secondary-sub-visibility", args ? "yes" : "no");
            }

            // Dual subtitles: set secondary position
            if (ev === "secondary-sub-pos") {
                mpv.setProperty("secondary-sub-pos", args);
            }

            if (ev === "control-event") wakeupEvent();
            if (ev === "wakeup") wakeupEvent();
            if (ev === "set-window-mode") {
                transport.dualPlayerMode = (args === "player");
                onWindowMode(args);
            }
            if (ev === "open-external") Qt.openUrlExternally(args)
            if (ev === "win-focus" && !root.visible) {
                showWindow();
            }
            if (ev === "win-set-visibility") {
                if (args.hasOwnProperty('fullscreen')) {
                    setFullScreen(args.fullscreen);
                }
            }
            if (ev === "autoupdater-notif-clicked" && autoUpdater.onNotifClicked) {
                autoUpdater.onNotifClicked();
            }
            if (ev === "screensaver-toggle") shouldDisableScreensaver(args.disabled)
            if (ev === "file-close") fileDialog.close()
            if (ev === "file-open") {
              if (typeof args !== "undefined") {
                var fileDialogDefaults = {
                  title: "Please choose",
                  selectExisting: true,
                  selectFolder: false,
                  selectMultiple: false,
                  nameFilters: [],
                  selectedNameFilter: "",
                  data: null
                }
                Object.keys(fileDialogDefaults).forEach(function(key) {
                  fileDialog[key] = args.hasOwnProperty(key) ? args[key] : fileDialogDefaults[key]
                })
              }
              fileDialog.open()
            }
        }

        // events that we want to wait for the app to initialize
        property variant queued: []
        function queueEvent() { 
            if (transport.queued) transport.queued.push(arguments)
            else transport.event.apply(transport, arguments)
        }
        function flushQueue() {
            if (transport.queued) transport.queued.forEach(function(args) { transport.event.apply(transport, args) })
            transport.queued = null;
        }
    }


    // Utilities
    function onWindowMode(mode) {
        shouldDisableScreensaver(mode === "player")
    }

    function wakeupEvent() {
        shouldDisableScreensaver(true)
        timerScreensaver.restart()
    }

    function shouldDisableScreensaver(condition) {
        if (condition === screenSaver.disabled) return;
        condition ? screenSaver.disable() : screenSaver.enable();
        screenSaver.disabled = condition;
    }

    function isPlayerPlaying() {
        return root.visible && typeof(mpv.getProperty("path"))==="string" && !mpv.getProperty("pause")
    }

    // Received external message
    function onAppMessageReceived(instance, message) {
        message = message.toString(); // cause it may be QUrl
        showWindow();
        if (message !== "SHOW") {
                onAppOpenMedia(message);
        }
    }

    // May be called from a message (from another app instance) or when app is initialized with an arg
    function onAppOpenMedia(message) {
        var url = (message.indexOf('://') > -1 || message.indexOf('magnet:') === 0) ? message : 'file://'+message;
        transport.queueEvent("open-media", url)
    }

    function quitApp() {
        root.quitting = true;
        webView.destroy();
        systemTray.hideIconTray();
        streamingServer.kill();
        streamingServer.waitForFinished(1500);
        Qt.quit();
    }

    /* With help Connections object
     * set connections with System tray class
     * */
    Connections {
        target: systemTray

        function onSignalIconMenuAboutToShow() {
            systemTray.updateIsOnTop((root.flags & Qt.WindowStaysOnTopHint) === Qt.WindowStaysOnTopHint);
	        systemTray.updateVisibleAction(root.visible);
        }

        function onSignalShow() {
            if(root.visible) {
                root.hide();
            } else {
                showWindow();
            }
        }

        function onSignalAlwaysOnTop() {
            root.raise()
            if (root.flags & Qt.WindowStaysOnTopHint) {
                root.flags &= ~Qt.WindowStaysOnTopHint;
            } else {
                root.flags |= Qt.WindowStaysOnTopHint;
            }
        }
 
        // The signal - close the application by ignoring the check-box
        function onSignalQuit() {
            quitApp();
        }
 
        // Minimize / maximize the window by clicking on the default system tray
        function onSignalIconActivated() {
           showWindow();
       }
    }

    // Screen saver - enable & disable
    ScreenSaver {
        id: screenSaver
        property bool disabled: false // track last state so we don't call it multiple times
    }
    // This is needed so that 300s after the remote control has been used, we can re-enable the screensaver
    // (if the player is not playing)
    Timer {
        id: timerScreensaver
        interval: 300000
        running: false
        onTriggered: function () { shouldDisableScreensaver(isPlayerPlaying()) }
    }

    // Clipboard proxy
    Clipboard {
        id: clipboard
    }

    //
    // Streaming server
    //
    Process {
        id: streamingServer
        property string errMessage:
            "Error while starting streaming server. Please try to restart stremio. If it happens again please contact the Stremio support team for assistance"
        property int errors: 0
        property bool fastReload: false

        onStarted: function() { stayAliveStreamingServer.stop() }
        onFinished: function(code, status) { 
            // status -> QProcess::CrashExit is 1
            if (!streamingServer.fastReload && errors < 5 && (code !== 0 || status !== 0) && !root.quitting) {
                transport.queueEvent("server-crash", {"code": code, "log": streamingServer.getErrBuff()});

                errors++
                showStreamingServerErr(code)
            }

            if (streamingServer.fastReload) {
                console.log("Streaming server: performing fast re-load")
                streamingServer.fastReload = false
                root.launchServer()
            } else {
                stayAliveStreamingServer.start()
            }
        }
        onAddressReady: function (address) {
            transport.serverAddress = address
            transport.event("server-address", address)
        }
        onErrorThrown: function (error) {
            if (root.quitting) return; // inhibits errors during quitting
            if (streamingServer.fastReload && error == 1) return; // inhibit errors during fast reload mode;
                                                                  // we'll unset that after we've restarted the server
            transport.queueEvent("server-crash", {"code": error, "log": streamingServer.getErrBuff()});
            showStreamingServerErr(error)
       }
    }
    function showStreamingServerErr(code) {
        errorDialog.text = streamingServer.errMessage
        errorDialog.detailedText = 'Stremio streaming server has thrown an error \nQProcess::ProcessError code: ' 
            + code + '\n\n' 
            + streamingServer.getErrBuff();
        errorDialog.visible = true
    }
    function launchServer() {
        var node_executable = applicationDirPath + "/node"
        if (Qt.platform.os === "windows") node_executable = applicationDirPath + "/stremio-runtime.exe"
        streamingServer.start(node_executable, 
            [applicationDirPath +"/server.js"].concat(Qt.application.arguments.slice(1)), 
            "EngineFS server started at "
        )
    }
    // TimerStreamingServer
    Timer {
        id: stayAliveStreamingServer
        interval: 10000
        running: false
        onTriggered: function () { root.launchServer() }
    }

    //
    // DualSubtitles Addon Server
    //
    Process {
        id: addonServer
        property int errors: 0

        onStarted: function() { stayAliveAddonServer.stop() }
        onFinished: function(code, status) {
            if (errors < 5 && (code !== 0 || status !== 0) && !root.quitting) {
                console.log("[DualSub] Addon server exited with code " + code + ", restarting...");
                errors++;
            }
            stayAliveAddonServer.start();
        }
        onAddressReady: function (address) {
            console.log("[DualSub] Addon server ready at: " + address);
        }
        onErrorThrown: function (error) {
            if (root.quitting) return;
            console.log("[DualSub] Addon server error: " + error);
        }
    }
    function launchAddonServer() {
        var node_executable = applicationDirPath + "/node"
        if (Qt.platform.os === "windows") node_executable = applicationDirPath + "/stremio-runtime.exe"
        var addonDir = applicationDirPath + "/DualSubtitles"
        addonServer.start(node_executable,
            [addonDir + "/index.js"],
            "HTTP addon accessible at:"
        )
    }
    Timer {
        id: stayAliveAddonServer
        interval: 10000
        running: false
        onTriggered: function () { root.launchAddonServer() }
    }

    //
    // Player
    //
    MpvObject {
        id: mpv
        anchors.fill: parent
        onMpvEvent: function(ev, args) {
            // === DUAL SUBTITLES: TRACK-LIST MONITORING ===
            if (ev === "mpv-prop-change" && args && args.name === "track-list") {
                var tracks = args.data;
                if (Array.isArray(tracks)) {
                    // Log all subtitle tracks for debugging (including external-filename)
                    var subTracks = [];
                    for (var d = 0; d < tracks.length; d++) {
                        if (tracks[d].type === "sub") {
                            subTracks.push({
                                id: tracks[d].id,
                                title: tracks[d].title || "(no title)",
                                lang: tracks[d].lang || "(no lang)",
                                selected: !!tracks[d].selected,
                                external: !!tracks[d].external,
                                extFile: tracks[d]["external-filename"] || "",
                                codec: tracks[d].codec || "?"
                            });
                        }
                    }
                    if (subTracks.length > 0) {
                        console.log("[DualSub] Track-list update — " + subTracks.length + " sub tracks:");
                        for (var dl = 0; dl < subTracks.length; dl++) {
                            var st = subTracks[dl];
                            var extInfo = st.external ? " extFile=" + st.extFile.substring(0, 80) : "";
                            console.log("[DualSub]   #" + st.id + " title='" + st.title + "' lang=" + st.lang + " sel=" + st.selected + " ext=" + st.external + extInfo + " codec=" + st.codec);
                        }
                        console.log("[DualSub]   dualActive=" + transport.dualSubtitlesActive + " secondaryTrackId=" + transport.dualSecondaryTrackId);
                    }

                    // Extract embedded (non-external) subtitle tracks for language detection
                    var embeddedList = [];
                    for (var em = 0; em < subTracks.length; em++) {
                        if (!subTracks[em].external && subTracks[em].lang !== "(no lang)") {
                            embeddedList.push({
                                id: subTracks[em].id,
                                lang: subTracks[em].lang,
                                title: subTracks[em].title,
                                codec: subTracks[em].codec
                            });
                        }
                    }
                    dualPanel.embeddedTracks = embeddedList;
                    dualPanel.updateAvailableLangs();

                    // Phase 1: If dual subtitles active, find DualSecondary track and assign secondary-sid + styles
                    if (transport.dualSubtitlesActive) {
                        for (var i = 0; i < tracks.length; i++) {
                            var t = tracks[i];
                            if (t.type === "sub" && t.external === true && t.title === "DualSecondary") {
                                if (transport.dualSecondaryTrackId !== t.id) {
                                    transport.dualSecondaryTrackId = t.id;
                                    // secondary-sid MUST be a string (not number) — mpv rejects double type
                                    mpv.setProperty("secondary-sid", "" + t.id);
                                    // Use "no" so mpv preserves our ASS styling from the proxy
                                    mpv.setProperty("secondary-sub-ass-override", "no");
                                    mpv.setProperty("secondary-sub-visibility", "yes");
                                    console.log("[DualSub] Phase1: Set secondary-sid=" + t.id + " with ASS styling");
                                }
                            }
                            // Handle primary track managed by mpv (after language change from panel)
                            if (t.type === "sub" && t.external === true && t.title === "DualPrimary") {
                                if (transport.dualPrimaryTrackId !== t.id) {
                                    transport.dualPrimaryTrackId = t.id;
                                    mpv.setProperty("sid", "" + t.id);
                                    mpv.setProperty("sub-ass-override", "no");
                                    mpv.setProperty("sub-visibility", "yes");
                                    console.log("[DualSub] Phase1: Set sid=" + t.id + " for DualPrimary");
                                }
                            }
                        }
                    }

                    // Phase 3: Cleanup if dual is active but DualSecondary track
                    // disappeared (video changed). Subtitle deselection is handled
                    // by the dualPollTimer's localStorage polling.
                    if (transport.dualSubtitlesActive) {
                        var secondaryExists = false;
                        var primaryExists = false;
                        for (var k = 0; k < tracks.length; k++) {
                            if (tracks[k].type === "sub" && tracks[k].title === "DualSecondary") secondaryExists = true;
                            if (tracks[k].type === "sub" && tracks[k].title === "DualPrimary") primaryExists = true;
                        }
                        if (!secondaryExists) {
                            console.log("[DualSub] Phase3: Cleanup (secondaryExists=false, video likely changed)");
                            mpv.cleanupDualSub();
                        }
                        // If primary track was managed but disappeared, reset the flag
                        if (transport.dualPrimaryManaged && !primaryExists) {
                            transport.dualPrimaryManaged = false;
                            transport.dualPrimaryTrackId = -1;
                            transport.dualPrimarySubUrl = "";
                        }
                    }
                }
            }

            transport.event(ev, args);
        }

        // Fetch secondary subtitle info from the addon and load it via secondary-sid
        // Uses /dual-fetch/ which triggers on-demand subtitle search if cache is empty
        function fetchDualSecondary(contentType, videoId) {
            var xhr = new XMLHttpRequest();
            var url = "http://127.0.0.1:7000/dual-fetch/" + encodeURIComponent(contentType) + "/" + encodeURIComponent(videoId);
            console.log("[DualSub] fetchDualSecondary: GET " + url);
            xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    console.log("[DualSub] XHR response: status=" + xhr.status + " body=" + xhr.responseText.substring(0, 300));
                    if (xhr.status === 200) {
                        try {
                            var info = JSON.parse(xhr.responseText);
                            // Always activate panel so user can change languages
                            transport.dualSubtitlesActive = true;
                            transport.dualContentType = contentType;
                            transport.dualVideoId = videoId;
                            dualPollTimer.failCount = 0;
                            dualPollTimer.stallCount = 0;
                            // Store available OpenSubtitles languages and refresh button list
                            dualPanel.opensubLangs = info.available || [];
                            dualPanel.secondaryIsEmbedded = false;
                            dualPanel.updateAvailableLangs();
                            if (info.secondaryUrl) {
                                transport.dualSecondarySubUrl = info.secondaryUrl;
                                transport.dualSecondaryStyle = info.style || null;
                                // Build styled ASS proxy URL using panel settings
                                var styledUrl = "http://127.0.0.1:7000/dual-styled-sub?url=" + encodeURIComponent(info.secondaryUrl)
                                    + "&fontSize=" + dualPanel.secFontSize
                                    + "&color=" + dualPanel.secColor
                                    + "&borderColor=" + dualPanel.secBorderColor
                                    + "&borderSize=" + dualPanel.secBorderSize
                                    + "&bold=" + (dualPanel.secBold ? "true" : "false")
                                    + "&alignment=" + (dualPanel.secPositionTop ? "8" : "2");
                                mpv.command(["sub-add", styledUrl, "auto", "DualSecondary"]);
                                console.log("[DualSub] Loading secondary (" + info.secondaryLang + "): " + styledUrl);
                            } else {
                                // No OpenSubtitles secondary — try embedded tracks as fallback
                                var embSec = dualPanel.findEmbeddedTrack(dualPanel.secSecondaryLang);
                                // If configured secondary lang not in embedded, try first available embedded track
                                if (!embSec && dualPanel.embeddedTracks.length > 0) {
                                    embSec = dualPanel.embeddedTracks[0];
                                    console.log("[DualSub] Configured secondary lang '" + dualPanel.secSecondaryLang + "' not in embedded, using first: #" + embSec.id + " lang=" + embSec.lang);
                                }
                                if (embSec) {
                                    var embSecLang = dualPanel.mapLangCode(embSec.lang) || embSec.lang;
                                    dualPanel.selectEmbeddedSecondary(embSec, embSecLang);
                                    console.log("[DualSub] Fallback to embedded secondary: track #" + embSec.id + " lang=" + embSec.lang);
                                }

                                // Also handle primary: if no OpenSubtitles at all, use embedded for primary too
                                if (info.available && info.available.length === 0 && dualPanel.embeddedTracks.length > 0) {
                                    var embPri = dualPanel.findEmbeddedTrack(dualPanel.secPrimaryLang);
                                    if (!embPri) {
                                        // Use a different embedded track than secondary if possible
                                        for (var et = 0; et < dualPanel.embeddedTracks.length; et++) {
                                            if (!embSec || dualPanel.embeddedTracks[et].id !== embSec.id) {
                                                embPri = dualPanel.embeddedTracks[et];
                                                break;
                                            }
                                        }
                                        // If only one track, use same for both (better than empty)
                                        if (!embPri && dualPanel.embeddedTracks.length > 0) embPri = dualPanel.embeddedTracks[0];
                                    }
                                    if (embPri) {
                                        var embPriLang = dualPanel.mapLangCode(embPri.lang) || embPri.lang;
                                        dualPanel.selectEmbeddedPrimary(embPri, embPriLang);
                                        console.log("[DualSub] Fallback to embedded primary: track #" + embPri.id + " lang=" + embPri.lang);
                                    }
                                }

                                if (!embSec) {
                                    console.log("[DualSub] No embedded tracks found for: " + videoId + " — panel active for language selection");
                                }
                            }
                        } catch (e) {
                            console.log("[DualSub] Error parsing dual-fetch response: " + e);
                            dualPollTimer.failCount++;
                        }
                    } else {
                        console.log("[DualSub] dual-fetch request failed: " + xhr.status);
                        dualPollTimer.failCount++;
                    }
                }
            };
            xhr.send();
        }

        // Cleanup dual subtitle state
        function cleanupDualSub() {
            mpv.setProperty("secondary-sid", "no");
            // Only sub-remove external tracks (not embedded ones)
            if (transport.dualSecondaryTrackId > 0 && transport.dualSecondarySubUrl) {
                mpv.command(["sub-remove", transport.dualSecondaryTrackId.toString()]);
            }
            // Cleanup primary if managed by mpv
            if (transport.dualPrimaryManaged && transport.dualPrimaryTrackId > 0 && transport.dualPrimarySubUrl) {
                mpv.command(["sub-remove", transport.dualPrimaryTrackId.toString()]);
            }
            transport.dualSubtitlesActive = false;
            transport.dualSecondarySubUrl = "";
            transport.dualSecondaryTrackId = -1;
            transport.dualSecondaryStyle = null;
            transport.dualContentType = "";
            transport.dualVideoId = "";
            transport.dualPrimaryTrackId = -1;
            transport.dualPrimarySubUrl = "";
            transport.dualPrimaryManaged = false;
            dualPanel.secondaryIsEmbedded = false;
            dualPanel.opensubLangs = [];
            dualPanel.embeddedTracks = [];
            dualPanel.availableLangs = [];
            console.log("[DualSub] Cleaned up dual subtitles");
        }

        Component.onCompleted: {
            mpv.observeProperty("track-list");
        }
    }

    // === DUAL SUBTITLES: localStorage polling for detection ===
    // Stremio v4.4 web UI renders addon subtitles via HTML overlay (not mpv sub-add).
    // We detect when the user selects "DUAL ..." by polling localStorage, then load
    // only the SECONDARY subtitle via mpv secondary-sid for independent control.
    // Primary is rendered by the web UI's HTML overlay normally.
    Timer {
        id: dualPollTimer
        interval: 3000
        running: true
        repeat: true
        property bool pendingCheck: false
        property string lastActivatedVideoKey: ""
        property int failCount: 0
        property int stallCount: 0  // counts polls where isDual but not active and not retrying

        onTriggered: {
            if (dualPollTimer.pendingCheck) return;

            // Only poll when content is playing
            var mpvPath = mpv.getProperty("path");
            if (typeof mpvPath !== "string" || mpvPath === "") {
                if (transport.dualSubtitlesActive) {
                    console.log("[DualSub] Content stopped, cleaning up dual");
                    mpv.cleanupDualSub();
                }
                dualPollTimer.lastActivatedVideoKey = "";
                dualPollTimer.failCount = 0;
                dualPollTimer.stallCount = 0;
                return;
            }

            dualPollTimer.pendingCheck = true;

            // Read subtitle selection + type + videoId from the web UI hash
            // Hash format: #/player/{type}/{imdbId}/{videoId}/...
            var jsCode = "(function() { " +
                "if(!window._dualActivitySetup){window._dualActivitySetup=true;function u(){window._dualLastActivity=Date.now();}document.addEventListener('mousemove',u,true);document.addEventListener('keydown',u,true);document.addEventListener('click',u,true);document.addEventListener('touchstart',u,true);}" +
                "var subs = localStorage.getItem('subtitles') || ''; " +
                "var rawHash = window.location.hash || ''; " +
                "var parts = rawHash.split('/'); " +
                "var type = parts.length > 2 ? parts[2] : ''; " +
                "var videoId = ''; " +
                "if (parts.length > 4) { try { videoId = decodeURIComponent(parts[4]); } catch(e) { videoId = parts[4]; } } " +
                "return JSON.stringify({ subtitles: subs, type: type, videoId: videoId, hash: rawHash.substring(0, 200) }); " +
                "})()";

            webView.runJavaScript(jsCode, function(result) {
                try {
                    var data = JSON.parse(result);
                    var isDual = (typeof data.subtitles === "string" && data.subtitles.indexOf("DUAL ") === 0);
                    var videoId = data.videoId || "";
                    var contentType = data.type || "";

                    // Log hash once per session for debugging
                    if (isDual && dualPollTimer.failCount === 0 && !transport.dualSubtitlesActive) {
                        console.log("[DualSub] Hash: " + (data.hash || "(empty)"));
                        console.log("[DualSub] Parsed: type=" + contentType + " videoId=" + videoId);
                    }

                    if (isDual && !transport.dualSubtitlesActive) {
                        // DUAL selected but not active — try to activate
                        // Retry if: new video, or previous failures (up to 5), or stalled (XHR silently failed)
                        var isNewVideo = (videoId !== dualPollTimer.lastActivatedVideoKey);
                        var hasRetriesLeft = (dualPollTimer.failCount > 0 && dualPollTimer.failCount < 5);
                        dualPollTimer.stallCount++;
                        var isStalled = (dualPollTimer.stallCount >= 3); // force retry after ~9s of no progress
                        var shouldTry = isNewVideo || hasRetriesLeft || isStalled;
                        if (videoId !== "" && contentType !== "" && shouldTry) {
                            console.log("[DualSub] DUAL detected ('" + data.subtitles + "'), type=" + contentType + " videoId=" + videoId + " fail=" + dualPollTimer.failCount + " stall=" + dualPollTimer.stallCount);
                            dualPollTimer.stallCount = 0;
                            mpv.fetchDualSecondary(contentType, videoId);
                            dualPollTimer.lastActivatedVideoKey = videoId;
                        } else if (videoId === "") {
                            // No videoId in hash — fall back to /dual-latest
                            console.log("[DualSub] DUAL detected but no videoId in hash, trying /dual-latest");
                            var xhr = new XMLHttpRequest();
                            xhr.open("GET", "http://127.0.0.1:7000/dual-latest");
                            xhr.onreadystatechange = function() {
                                if (xhr.readyState === XMLHttpRequest.DONE) {
                                    if (xhr.status === 200) {
                                        try {
                                            var info = JSON.parse(xhr.responseText);
                                            if (info.active && info.secondaryUrl && info.videoKey !== dualPollTimer.lastActivatedVideoKey) {
                                                console.log("[DualSub] Activating from /dual-latest, videoKey=" + info.videoKey);
                                                transport.dualSubtitlesActive = true;
                                                transport.dualSecondarySubUrl = info.secondaryUrl;
                                                transport.dualSecondaryStyle = info.style || null;
                                                mpv.command(["sub-add", info.secondaryUrl, "auto", "DualSecondary"]);
                                                dualPollTimer.lastActivatedVideoKey = info.videoKey;
                                            }
                                        } catch (e) {
                                            console.log("[DualSub] Error parsing dual-latest: " + e);
                                        }
                                    }
                                    dualPollTimer.pendingCheck = false;
                                }
                            };
                            xhr.send();
                            return; // pendingCheck cleared in XHR callback
                        }
                    } else if (!isDual && transport.dualSubtitlesActive) {
                        // DUAL deselected — cleanup
                        console.log("[DualSub] DUAL subtitle deselected (now: '" + data.subtitles + "'), cleaning up");
                        mpv.cleanupDualSub();
                        dualPollTimer.lastActivatedVideoKey = "";
                        dualPollTimer.failCount = 0;
                        dualPollTimer.stallCount = 0;
                    }
                } catch (e) {
                    // runJavaScript might fail if page not loaded yet — ignore
                }
                dualPollTimer.pendingCheck = false;
            });
        }
    }

    //
    // Main UI (via WebEngineView)
    //
    function getWebUrl() {
        var params = "?loginFlow=desktop"
        var args = Qt.application.arguments
        var shortVer = Qt.application.version.split('.').slice(0, 2).join('.')

        var webuiArg = "--webui-url="
        for (var i=0; i!=args.length; i++) {
            if (args[i].indexOf(webuiArg) === 0) return args[i].slice(webuiArg.length)
        }

        if (args.indexOf("--development") > -1 || debug)
            return "http://127.0.0.1:11470/#"+params

        if (args.indexOf("--staging") > -1)
            return "https://staging.strem.io/#"+params

        return "https://app.strem.io/shell-v"+shortVer+"/#"+params;
    }

    Timer {
        id: retryTimer
        interval: 1000
        running: false
        onTriggered: function () {
            webView.tries++
            // we want to revert to the mainUrl in case the URL we were at was the one that caused the crash
            //webView.reload()
            webView.url = webView.mainUrl;
        }
    }
    function injectJS() {
        splashScreen.visible = false
        pulseOpacity.running = false
        removeSplashTimer.running = false
        webView.webChannel.registerObject( 'transport', transport )
        // Try-catch to be able to return the error as result, but still throw it in the client context
        // so it can be caught and reported
        var injectedJS = "try { initShellComm() } " +
                "catch(e) { setTimeout(function() { throw e }); e.message || JSON.stringify(e) }"
        webView.runJavaScript(injectedJS, function(err) {
            if (!err) {
                webView.tries = 0
            } else {
                errorDialog.text = "User Interface could not be loaded.\n\nPlease try again later or contact the Stremio support team for assistance."
                errorDialog.detailedText = err
                errorDialog.visible = true

                console.error(err)
            }
        });
    }

    // We want to remove the splash after a minute
    Timer {
        id: removeSplashTimer
        interval: 90000
        running: true
        repeat: false
        onTriggered: function () {
            webView.backgroundColor = "transparent"
            injectJS()
        }
    }

    WebEngineView {
        id: webView;

        focus: true

        readonly property string mainUrl: getWebUrl()
        
        url: webView.mainUrl;
        anchors.fill: parent
        backgroundColor: "transparent";
        property int tries: 0

        readonly property int maxTries: 20

        Component.onCompleted: function() {
            console.log("Loading web UI from URL: "+webView.mainUrl)

            webView.profile.httpUserAgent = webView.profile.httpUserAgent+' StremioShell/'+Qt.application.version

            // for more info, see
            // https://github.com/adobe/chromium/blob/master/net/disk_cache/backend_impl.cc - AdjustMaxCacheSize, 
            // https://github.com/adobe/chromium/blob/master/net/disk_cache/backend_impl.cc#L2094
            webView.profile.httpCacheMaximumSize = 209715200 // 200 MB
        }

        onLoadingChanged: function(loadRequest) {
            // hack for webEngineView changing it's background color on crashes
            webView.backgroundColor = "transparent"

            var successfullyLoaded = loadRequest.status == WebEngineView.LoadSucceededStatus
            if (successfullyLoaded || webView.tries > 0) {
                // show the webview if the loading is failing
                // can fail because of many reasons, including captive portals
                splashScreen.visible = false
                pulseOpacity.running = false
            }

            if (successfullyLoaded) {
                injectJS()
            }

            var shouldRetry = loadRequest.status == WebEngineView.LoadFailedStatus ||
                    loadRequest.status == WebEngineView.LoadStoppedStatus
            if ( shouldRetry && webView.tries < webView.maxTries) {
                retryTimer.restart()
            }
        }

        onRenderProcessTerminated: function(terminationStatus, exitCode) {
            console.log("render process terminated with code "+exitCode+" and status: "+terminationStatus)
            
            // hack for webEngineView changing it's background color on crashes
            webView.backgroundColor = "black"

            retryTimer.restart()

            // send an event for the crash, but since the web UI is not working, reset the queue and queue it
            transport.queued = []
            transport.queueEvent("render-process-terminated", { exitCode: exitCode, terminationStatus: terminationStatus, url: webView.url })

        }

        // WARNING: does not work..for some reason: "Scripts may close only the windows that were opened by it."
        // onWindowCloseRequested: function() {
        //     root.visible = false;
        //     Qt.quit()
        // }

        // In the app, we use open-external IPC signal, but make sure this works anyway
        property string hoveredUrl: ""
        onLinkHovered: webView.hoveredUrl = hoveredUrl
        onNewViewRequested: function(req) { if (req.userInitiated) Qt.openUrlExternally(webView.hoveredUrl) }

        // FIXME: When is this called?
        onFullScreenRequested: function(req) {
            setFullScreen(req.toggleOn);
            req.accept();
        }

        // Prevent navigation
        onNavigationRequested: function(req) {
            // WARNING: @TODO: perhaps we need a better way to parse URLs here
            var allowedHost = webView.mainUrl.split('/')[2]
            var targetHost = req.url.toString().split('/')[2]
            if (allowedHost != targetHost && (req.isMainFrame || targetHost !== 'www.youtube.com')) {
                 console.log("onNavigationRequested: disallowed URL "+req.url.toString());
                 req.action = WebEngineView.IgnoreRequest;
            }
        }

        Menu {
            id: ctxMenu
            MenuItem {
                text: "Undo"
                shortcut: StandardKey.Undo
                onTriggered: webView.triggerWebAction(WebEngineView.Undo)
            }
            MenuItem {
                text: "Redo"
                shortcut: StandardKey.Redo
                onTriggered: webView.triggerWebAction(WebEngineView.Redo)
            }
            MenuSeparator { }
            MenuItem {
                text: "Cut"
                shortcut: StandardKey.Cut
                onTriggered: webView.triggerWebAction(WebEngineView.Cut)
            }
            MenuItem {
                text: "Copy"
                shortcut: StandardKey.Copy
                onTriggered: webView.triggerWebAction(WebEngineView.Copy)
            }
            MenuItem {
                text: "Paste"
                shortcut: StandardKey.Paste
                onTriggered: webView.triggerWebAction(WebEngineView.Paste)
            }
            MenuSeparator { }
            MenuItem {
                text: "Select All"
                shortcut: StandardKey.SelectAll
                onTriggered: webView.triggerWebAction(WebEngineView.SelectAll)
            }
        }

        // Prevent ctx menu
        onContextMenuRequested: function(request) {
            request.accepted = true;
            // Allow menu inside editalbe objects
            if (request.isContentEditable) {
                ctxMenu.popup();
            }
        }

        Action {
            shortcut: StandardKey.Paste
            onTriggered: webView.triggerWebAction(WebEngineView.Paste)
        }

        DropArea {
            anchors.fill: parent
            onDropped: function(dropargs){
                var args = JSON.parse(JSON.stringify(dropargs))
                transport.event("dragdrop", args.urls)
            }
        }
        webChannel: wChannel
    }

    WebChannel {
        id: wChannel
    }

    //
    // Splash screen
    // Must be over the UI
    //
    Rectangle {
        id: splashScreen;
        color: "#0c0b11";
        anchors.fill: parent;
        Image {
            id: splashLogo
            source: "qrc:///images/stremio.png"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation {
                id: pulseOpacity
                running: true
                NumberAnimation { target: splashLogo; property: "opacity"; to: 1.0; duration: 600;
                    easing.type: Easing.Linear; }
                NumberAnimation { target: splashLogo; property: "opacity"; to: 0.3; duration: 600;
                    easing.type: Easing.Linear; }
                loops: Animation.Infinite
            }
        }
    }

    // === DUAL SUBTITLES: Settings Toggle Button ===
    // Uses activity polling via injected JS to detect mouse/key events in WebEngineView
    Timer {
        id: dualActivityTimer
        interval: 500
        running: transport.dualSubtitlesActive
        repeat: true
        property real lastActivity: 0
        onTriggered: {
            webView.runJavaScript("window._dualLastActivity||0", function(ts) {
                if (typeof ts === "number" && ts > dualActivityTimer.lastActivity) {
                    dualActivityTimer.lastActivity = ts;
                    dualShowBtn();
                }
            });
        }
    }
    Timer {
        id: dualBtnHideTimer
        interval: 3000
        repeat: false
        onTriggered: dualBtnVisible = false
    }
    property bool dualBtnVisible: false
    function dualShowBtn() {
        if (transport.dualSubtitlesActive) {
            dualBtnVisible = true;
            dualBtnHideTimer.restart();
        }
    }
    Rectangle {
        id: dualSettingsBtn
        visible: transport.dualSubtitlesActive && !dualPanel.visible && dualBtnVisible
        width: 44; height: 44; radius: 22
        color: dualBtnMa.containsMouse ? "#CC4444AA" : "#AA333366"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.bottomMargin: 80
        z: 999
        Text {
            text: "S\u2082"
            color: "#FFFF00"
            font.pixelSize: 18
            font.bold: true
            anchors.centerIn: parent
        }
        MouseArea {
            id: dualBtnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dualPanel.visible = true
        }
    }

    // === DUAL SUBTITLES: Persistent Settings ===
    Settings {
        id: dualSettings
        category: "DualSubtitles"
        // Secondary track settings
        property int fontSize: 20
        property string color: "FFFF00"
        property string borderColor: "000000"
        property int borderSize: 2
        property bool bold: false
        property bool positionTop: true
        // Primary track settings
        property int priFontSize: 24
        property string priColor: "FFFFFF"
        property string priBorderColor: "000000"
        property int priBorderSize: 2
        property bool priBold: true
        property bool priPositionTop: false
        // Language settings
        property string primaryLang: "ita"
        property string secondaryLang: "spa"
        // Letterbox margins
        property bool useMargins: true
    }

    // === DUAL SUBTITLES: Settings Panel ===
    Rectangle {
        id: dualPanel
        visible: false
        width: 360
        height: Math.min(dualPanelCol.height + 32, parent.height - 100)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 20
        anchors.topMargin: 60
        color: "#EE1a1a2e"
        border.color: "#555577"
        border.width: 1
        radius: 10
        z: 1000

        // Settings state — secondary track
        property int secFontSize: dualSettings.fontSize
        property string secColor: dualSettings.color
        property string secBorderColor: dualSettings.borderColor
        property int secBorderSize: dualSettings.borderSize
        property bool secBold: dualSettings.bold
        property bool secPositionTop: dualSettings.positionTop
        property real secDelay: 0.0
        // Settings state — primary track
        property int priFontSize: dualSettings.priFontSize
        property string priColor: dualSettings.priColor
        property string priBorderColor: dualSettings.priBorderColor
        property int priBorderSize: dualSettings.priBorderSize
        property bool priBold: dualSettings.priBold
        property bool priPositionTop: dualSettings.priPositionTop
        property real priDelay: 0.0
        // Language settings
        property string secPrimaryLang: dualSettings.primaryLang
        property string secSecondaryLang: dualSettings.secondaryLang
        property bool useMargins: dualSettings.useMargins
        property bool langSearching: false

        // Available languages: only these are shown as buttons
        property var opensubLangs: []         // from OpenSubtitles addon response
        property var embeddedTracks: []       // [{id, lang, title, codec}] from track-list
        property var availableLangs: []       // computed union of opensub + embedded + selected
        // Whether the current secondary is an embedded track (no ASS proxy)
        property bool secondaryIsEmbedded: false

        // Variant tracking: maps lang code -> array of {index, url, title}
        property var primaryVariants: ({})   // e.g. {"ita": [{index:0, url:"...", title:"..."},...]}
        property var secondaryVariants: ({})
        // Currently selected variant index per lang
        property var primaryVariantIdx: ({})   // e.g. {"ita": 0}
        property var secondaryVariantIdx: ({})

        // Persist settings when changed — secondary
        onSecFontSizeChanged: dualSettings.fontSize = secFontSize
        onSecColorChanged: dualSettings.color = secColor
        onSecBorderColorChanged: dualSettings.borderColor = secBorderColor
        onSecBorderSizeChanged: dualSettings.borderSize = secBorderSize
        onSecBoldChanged: dualSettings.bold = secBold
        onSecPositionTopChanged: dualSettings.positionTop = secPositionTop
        // Persist settings when changed — primary
        onPriFontSizeChanged: dualSettings.priFontSize = priFontSize
        onPriColorChanged: dualSettings.priColor = priColor
        onPriBorderColorChanged: dualSettings.priBorderColor = priBorderColor
        onPriBorderSizeChanged: dualSettings.priBorderSize = priBorderSize
        onPriBoldChanged: dualSettings.priBold = priBold
        onPriPositionTopChanged: dualSettings.priPositionTop = priPositionTop
        // Persist language settings
        onSecPrimaryLangChanged: dualSettings.primaryLang = secPrimaryLang
        onSecSecondaryLangChanged: dualSettings.secondaryLang = secSecondaryLang
        // Persist margins setting
        onUseMarginsChanged: {
            dualSettings.useMargins = useMargins;
            var val = useMargins ? "yes" : "no";
            mpv.setProperty("sub-use-margins", val);
            mpv.setProperty("sub-ass-force-margins", val);
            mpv.setProperty("secondary-sub-use-margins", val);
            mpv.setProperty("secondary-sub-ass-force-margins", val);
            console.log("[DualSub] Letterbox margins: " + val);
        }

        // Hide when dual deactivated
        Connections {
            target: transport
            onDualSubtitlesActiveChanged: {
                if (!transport.dualSubtitlesActive) {
                    dualPanel.visible = false;
                    dualBtnVisible = false;
                    // Remove CSS overlay hide if primary was managed
                    if (transport.dualPrimaryManaged) {
                        webView.runJavaScript("(function(){ var s=document.getElementById('dual-hide-overlay'); if(s) s.remove(); })()");
                    }
                } else {
                    dualShowBtn();
                    // Inject activity tracker for auto-hide polling
                    webView.runJavaScript("(function(){if(window._dualActivitySetup)return;window._dualActivitySetup=true;function u(){window._dualLastActivity=Date.now();}document.addEventListener('mousemove',u,true);document.addEventListener('keydown',u,true);document.addEventListener('click',u,true);document.addEventListener('touchstart',u,true);u();})()");
                }
            }
        }

        // Debounce style reload (ASS re-generation)
        Timer {
            id: dualReloadTimer
            interval: 400
            repeat: false
            onTriggered: dualPanel.doReload()
        }

        function scheduleReload() { dualReloadTimer.restart(); }

        function doReload() {
            if (!transport.dualSubtitlesActive) return;
            // Embedded tracks don't use the ASS proxy, nothing to reload
            if (dualPanel.secondaryIsEmbedded) return;
            if (!transport.dualSecondarySubUrl) return;
            // If primary is mpv-managed, reload both tracks
            if (transport.dualPrimaryManaged) { dualPanel.doReloadBoth(); return; }
            if (transport.dualSecondaryTrackId > 0) {
                mpv.setProperty("secondary-sid", "no");
                mpv.command(["sub-remove", "" + transport.dualSecondaryTrackId]);
                transport.dualSecondaryTrackId = -1;
            }
            var u = "http://127.0.0.1:7000/dual-styled-sub?url=" + encodeURIComponent(transport.dualSecondarySubUrl)
                + "&fontSize=" + dualPanel.secFontSize
                + "&color=" + dualPanel.secColor
                + "&borderColor=" + dualPanel.secBorderColor
                + "&borderSize=" + dualPanel.secBorderSize
                + "&bold=" + (dualPanel.secBold ? "true" : "false")
                + "&alignment=" + (dualPanel.secPositionTop ? "8" : "2");
            mpv.command(["sub-add", u, "auto", "DualSecondary"]);
            console.log("[DualSub] Style reload: sec size=" + secFontSize + " color=#" + secColor + " pos=" + (secPositionTop ? "top" : "bottom"));
        }

        // Search for subtitles with new secondary language
        function searchLanguages(newSecLang) {
            if (!transport.dualSubtitlesActive || transport.dualContentType === "" || transport.dualVideoId === "") {
                // No addon context — try embedded tracks directly
                var embFallback = dualPanel.findEmbeddedTrack(newSecLang);
                if (embFallback) dualPanel.selectEmbeddedSecondary(embFallback, newSecLang);
                return;
            }
            dualPanel.langSearching = true;
            var xhr = new XMLHttpRequest();
            var url = "http://127.0.0.1:7000/dual-search/" + encodeURIComponent(transport.dualContentType)
                + "/" + encodeURIComponent(transport.dualVideoId)
                + "?primaryLang=" + dualPanel.secPrimaryLang
                + "&secondaryLang=" + newSecLang;
            console.log("[DualSub] Language search: " + url);
            xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    dualPanel.langSearching = false;
                    if (xhr.status === 200) {
                        try {
                            var info = JSON.parse(xhr.responseText);
                            // Store variants for both languages
                            if (info.primaryVariants) {
                                var pv = dualPanel.primaryVariants;
                                pv[dualPanel.secPrimaryLang] = info.primaryVariants;
                                dualPanel.primaryVariants = pv;
                            }
                            if (info.secondaryVariants) {
                                var sv = dualPanel.secondaryVariants;
                                sv[newSecLang] = info.secondaryVariants;
                                dualPanel.secondaryVariants = sv;
                            }
                            if (info.found && info.secondaryUrl) {
                                dualPanel.secSecondaryLang = newSecLang;
                                dualPanel.secondaryIsEmbedded = false;
                                transport.dualSecondarySubUrl = info.secondaryUrl;
                                // Reset variant index for this language
                                var si = dualPanel.secondaryVariantIdx;
                                si[newSecLang] = 0;
                                dualPanel.secondaryVariantIdx = si;
                                console.log("[DualSub] Language changed, new secondary: " + info.secondaryLang + " " + info.secondaryUrl);
                                dualPanel.doReload();
                            } else {
                                // Fallback to embedded tracks
                                var embedded = dualPanel.findEmbeddedTrack(newSecLang);
                                if (embedded) {
                                    dualPanel.selectEmbeddedSecondary(embedded, newSecLang);
                                } else {
                                    console.log("[DualSub] Language not found: " + newSecLang + " (available: " + JSON.stringify(dualPanel.availableLangs) + ")");
                                }
                            }
                        } catch(e) {
                            console.log("[DualSub] Language search parse error: " + e);
                        }
                    }
                }
            };
            xhr.send();
        }

        // Search for subtitles with new primary language — switches primary to mpv-managed
        function searchPrimaryLanguage(newPriLang) {
            if (!transport.dualSubtitlesActive) return;
            // If no addon context, try embedded tracks directly
            if (transport.dualContentType === "" || transport.dualVideoId === "") {
                var embFallback = dualPanel.findEmbeddedTrack(newPriLang);
                if (embFallback) dualPanel.selectEmbeddedPrimary(embFallback, newPriLang);
                return;
            }
            dualPanel.langSearching = true;
            var xhr = new XMLHttpRequest();
            var url = "http://127.0.0.1:7000/dual-search/" + encodeURIComponent(transport.dualContentType)
                + "/" + encodeURIComponent(transport.dualVideoId)
                + "?primaryLang=" + newPriLang
                + "&secondaryLang=" + dualPanel.secSecondaryLang;
            console.log("[DualSub] Primary language search: " + url);
            xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    dualPanel.langSearching = false;
                    if (xhr.status === 200) {
                        try {
                            var info = JSON.parse(xhr.responseText);
                            // Store variants for both languages
                            if (info.primaryVariants) {
                                var pv = dualPanel.primaryVariants;
                                pv[newPriLang] = info.primaryVariants;
                                dualPanel.primaryVariants = pv;
                            }
                            if (info.secondaryVariants) {
                                var sv = dualPanel.secondaryVariants;
                                sv[dualPanel.secSecondaryLang] = info.secondaryVariants;
                                dualPanel.secondaryVariants = sv;
                            }
                            if (info.found && info.primaryUrl) {
                                dualPanel.secPrimaryLang = newPriLang;
                                transport.dualPrimarySubUrl = info.primaryUrl;
                                // Reset variant index for this language
                                var pi = dualPanel.primaryVariantIdx;
                                pi[newPriLang] = 0;
                                dualPanel.primaryVariantIdx = pi;
                                // Also update secondary if returned
                                if (info.secondaryUrl) transport.dualSecondarySubUrl = info.secondaryUrl;
                                // Switch to mpv-managed primary
                                transport.dualPrimaryManaged = true;
                                // Hide Stremio HTML subtitle overlay
                                webView.runJavaScript("(function(){ if(!document.getElementById('dual-hide-overlay')){ var s=document.createElement('style'); s.id='dual-hide-overlay'; s.textContent='video::cue{visibility:hidden!important;color:transparent!important} [class*=\"subtitle\"]{visibility:hidden!important} [class*=\"Subtitle\"]{visibility:hidden!important} [class*=\"cue-\"]{visibility:hidden!important}'; document.head.appendChild(s); }})()");
                                console.log("[DualSub] Primary language changed to " + newPriLang + ", switching to mpv-managed primary");
                                dualPanel.doReloadBoth();
                            } else {
                                // Fallback to embedded tracks
                                var embedded = dualPanel.findEmbeddedTrack(newPriLang);
                                if (embedded) {
                                    dualPanel.selectEmbeddedPrimary(embedded, newPriLang);
                                } else {
                                    console.log("[DualSub] Primary language not found: " + newPriLang);
                                }
                            }
                        } catch(e) {
                            console.log("[DualSub] Primary language search parse error: " + e);
                        }
                    }
                }
            };
            xhr.send();
        }

        // Reload both primary and secondary tracks (when primary is mpv-managed)
        function doReloadBoth() {
            if (!transport.dualSubtitlesActive) return;
            // Remove old secondary
            if (transport.dualSecondaryTrackId > 0) {
                mpv.setProperty("secondary-sid", "no");
                mpv.command(["sub-remove", "" + transport.dualSecondaryTrackId]);
                transport.dualSecondaryTrackId = -1;
            }
            // Remove old primary
            if (transport.dualPrimaryTrackId > 0) {
                mpv.command(["sub-remove", "" + transport.dualPrimaryTrackId]);
                transport.dualPrimaryTrackId = -1;
            }
            // Add new primary (using primary panel settings)
            if (transport.dualPrimarySubUrl) {
                var pu = "http://127.0.0.1:7000/dual-styled-sub?url=" + encodeURIComponent(transport.dualPrimarySubUrl)
                    + "&fontSize=" + dualPanel.priFontSize
                    + "&color=" + dualPanel.priColor
                    + "&borderColor=" + dualPanel.priBorderColor
                    + "&borderSize=" + dualPanel.priBorderSize
                    + "&bold=" + (dualPanel.priBold ? "true" : "false")
                    + "&alignment=" + (dualPanel.priPositionTop ? "8" : "2");
                mpv.command(["sub-add", pu, "auto", "DualPrimary"]);
            }
            // Add new secondary (using secondary panel settings)
            if (transport.dualSecondarySubUrl) {
                var su = "http://127.0.0.1:7000/dual-styled-sub?url=" + encodeURIComponent(transport.dualSecondarySubUrl)
                    + "&fontSize=" + dualPanel.secFontSize
                    + "&color=" + dualPanel.secColor
                    + "&borderColor=" + dualPanel.secBorderColor
                    + "&borderSize=" + dualPanel.secBorderSize
                    + "&bold=" + (dualPanel.secBold ? "true" : "false")
                    + "&alignment=" + (dualPanel.secPositionTop ? "8" : "2");
                mpv.command(["sub-add", su, "auto", "DualSecondary"]);
            }
            console.log("[DualSub] Reloaded both tracks (pri: size=" + priFontSize + " col=#" + priColor + " sec: size=" + secFontSize + " col=#" + secColor + ")");
        }

        // Select a specific variant for primary or secondary language
        // role: "primary" or "secondary", lang: language code, variantIndex: index in variants array
        function selectVariant(role, lang, variantIndex) {
            var variants = role === "primary" ? dualPanel.primaryVariants : dualPanel.secondaryVariants;
            var langVariants = variants[lang];
            if (!langVariants || variantIndex < 0 || variantIndex >= langVariants.length) return;
            var variant = langVariants[variantIndex];
            if (!variant || !variant.url) return;

            if (role === "primary") {
                var pi = dualPanel.primaryVariantIdx;
                pi[lang] = variantIndex;
                dualPanel.primaryVariantIdx = pi;
                transport.dualPrimarySubUrl = variant.url;
                transport.dualPrimaryManaged = true;
                webView.runJavaScript("(function(){ if(!document.getElementById('dual-hide-overlay')){ var s=document.createElement('style'); s.id='dual-hide-overlay'; s.textContent='video::cue{visibility:hidden!important;color:transparent!important} [class*=\"subtitle\"]{visibility:hidden!important} [class*=\"Subtitle\"]{visibility:hidden!important} [class*=\"cue-\"]{visibility:hidden!important}'; document.head.appendChild(s); }})()");
                console.log("[DualSub] Primary variant #" + variantIndex + " selected for " + lang);
                dualPanel.doReloadBoth();
            } else {
                var si = dualPanel.secondaryVariantIdx;
                si[lang] = variantIndex;
                dualPanel.secondaryVariantIdx = si;
                transport.dualSecondarySubUrl = variant.url;
                console.log("[DualSub] Secondary variant #" + variantIndex + " selected for " + lang);
                dualPanel.doReload();
            }
        }

        // Helper: get variant count for a lang
        function getVariantCount(role, lang) {
            var variants = role === "primary" ? dualPanel.primaryVariants : dualPanel.secondaryVariants;
            if (!variants || !variants[lang]) return 0;
            return variants[lang].length;
        }

        // Map 2-letter ISO 639-1 codes to 3-letter OpenSubtitles codes
        function mapLangCode(code) {
            if (!code || code === "(no lang)") return "";
            if (code.length >= 3) return code;
            var map = {
                "it": "ita", "en": "eng", "es": "spa", "fr": "fre", "de": "ger",
                "pt": "por", "ja": "jpn", "ko": "kor", "zh": "chi", "ar": "ara",
                "ru": "rus", "hi": "hin", "pl": "pol", "tr": "tur", "nl": "dut",
                "sv": "swe", "no": "nor", "da": "dan", "fi": "fin", "cs": "cze",
                "ro": "ron", "hu": "hun", "el": "ell", "he": "heb", "th": "tha",
                "vi": "vie", "id": "ind", "ms": "may", "hr": "hrv", "sl": "slv",
                "pb": "pob"
            };
            return map[code] || code;
        }

        // Rebuild the availableLangs list from opensub + embedded + selected
        function updateAvailableLangs() {
            var langs = [];
            for (var i = 0; i < opensubLangs.length; i++) {
                if (langs.indexOf(opensubLangs[i]) < 0) langs.push(opensubLangs[i]);
            }
            for (var j = 0; j < embeddedTracks.length; j++) {
                var eLang = mapLangCode(embeddedTracks[j].lang);
                if (eLang && langs.indexOf(eLang) < 0) langs.push(eLang);
            }
            // Always keep the currently selected languages visible
            if (secPrimaryLang && langs.indexOf(secPrimaryLang) < 0) langs.push(secPrimaryLang);
            if (secSecondaryLang && langs.indexOf(secSecondaryLang) < 0) langs.push(secSecondaryLang);
            availableLangs = langs;
        }

        // Find an embedded track matching a language code
        function findEmbeddedTrack(langCode) {
            for (var i = 0; i < embeddedTracks.length; i++) {
                if (mapLangCode(embeddedTracks[i].lang) === langCode) return embeddedTracks[i];
            }
            return null;
        }

        // Select an embedded track as secondary (no ASS proxy needed)
        function selectEmbeddedSecondary(track, langCode) {
            // Remove previously loaded external secondary track
            if (transport.dualSecondaryTrackId > 0 && transport.dualSecondarySubUrl) {
                mpv.setProperty("secondary-sid", "no");
                mpv.command(["sub-remove", "" + transport.dualSecondaryTrackId]);
            }
            dualPanel.secSecondaryLang = langCode;
            dualPanel.secondaryIsEmbedded = true;
            transport.dualSecondarySubUrl = "";  // no URL for embedded
            transport.dualSecondaryTrackId = track.id;
            mpv.setProperty("secondary-sid", "" + track.id);
            mpv.setProperty("secondary-sub-visibility", "yes");
            console.log("[DualSub] Using embedded track #" + track.id + " (" + track.lang + ") as secondary");
        }

        // Select an embedded track as primary
        function selectEmbeddedPrimary(track, langCode) {
            // Remove previously loaded external primary track
            if (transport.dualPrimaryManaged && transport.dualPrimaryTrackId > 0 && transport.dualPrimarySubUrl) {
                mpv.command(["sub-remove", "" + transport.dualPrimaryTrackId]);
            }
            dualPanel.secPrimaryLang = langCode;
            transport.dualPrimarySubUrl = "";
            transport.dualPrimaryManaged = false;
            transport.dualPrimaryTrackId = track.id;
            mpv.setProperty("sid", "" + track.id);
            mpv.setProperty("sub-visibility", "yes");
            console.log("[DualSub] Using embedded track #" + track.id + " (" + track.lang + ") as primary");
        }

        Flickable {
            id: dualPanelFlick
            anchors.fill: parent; anchors.margins: 16
            contentHeight: dualPanelCol.height
            clip: true; flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

        Column {
            id: dualPanelCol
            width: dualPanelFlick.width
            spacing: 8

            // --- Title bar ---
            Item {
                width: parent.width; height: 24
                Text {
                    text: "\u2699 Sottotitoli Duali"
                    color: "#FFFFFF"; font.pixelSize: 15; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "\u2715"
                    color: closeMa.containsMouse ? "#FFFFFF" : "#888888"
                    font.pixelSize: 18
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        id: closeMa; anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: dualPanel.visible = false
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: "#444466" }

            // --- Primary Language ---
            Text { text: "Lingua primaria" + (dualPanel.langSearching ? " \u23F3" : "") + (dualPanel.availableLangs.length === 0 ? " (caricamento...)" : ""); color: "#BBBBBB"; font.pixelSize: 13 }
            Flickable {
                width: parent.width; height: 34
                contentWidth: priLangRow.width; clip: true
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: priLangRow; spacing: 4
                    Repeater {
                        model: dualPanel.availableLangs
                        Rectangle {
                            id: priBtnRect
                            property int varCount: dualPanel.getVariantCount("primary", modelData)
                            property string lang: modelData
                            property bool isSelected: dualPanel.secPrimaryLang === modelData
                            property bool isEmbeddedOnly: dualPanel.opensubLangs.indexOf(modelData) < 0 && dualPanel.findEmbeddedTrack(modelData) !== null
                            width: priLangContent.width + 14; height: 28; radius: 4
                            color: isSelected ? "#44AA44" : "#333355"
                            border.color: isSelected ? "#88FF88" : (isEmbeddedOnly ? "#665544" : "#444466")
                            Row {
                                id: priLangContent
                                anchors.centerIn: parent; spacing: 3
                                Text { id: priLangText; text: priBtnRect.lang.toUpperCase() + (priBtnRect.isEmbeddedOnly ? " \uD83D\uDCCE" : ""); color: priBtnRect.isSelected ? "#FFF" : "#AAA"; font.pixelSize: 12; font.bold: priBtnRect.isSelected; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    visible: priBtnRect.isSelected && priBtnRect.varCount > 1
                                    spacing: 2; anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: priBtnRect.varCount
                                        Rectangle {
                                            width: 5; height: 5; radius: 3
                                            color: {
                                                var idx = dualPanel.primaryVariantIdx[priBtnRect.lang];
                                                return (idx !== undefined && idx === index) ? "#FFFFFF" : "#88AA88";
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (priBtnRect.lang !== dualPanel.secPrimaryLang) dualPanel.searchPrimaryLanguage(priBtnRect.lang); }
                                onPressAndHold: {
                                    if (priBtnRect.varCount > 1) {
                                        variantPopup.role = "primary";
                                        variantPopup.lang = priBtnRect.lang;
                                        variantPopup.variants = dualPanel.primaryVariants[priBtnRect.lang];
                                        variantPopup.currentIdx = dualPanel.primaryVariantIdx[priBtnRect.lang] || 0;
                                        var globalPos = priBtnRect.mapToItem(dualPanel, 0, priBtnRect.height);
                                        variantPopup.x = Math.min(Math.max(globalPos.x, 8), dualPanel.width - variantPopup.width - 8);
                                        variantPopup.y = globalPos.y + 4;
                                        variantPopup.visible = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- Secondary Language ---
            Text { text: "Lingua secondaria" + (dualPanel.langSearching ? " \u23F3" : ""); color: "#BBBBBB"; font.pixelSize: 13 }
            Flickable {
                width: parent.width; height: 34
                contentWidth: secLangRow.width; clip: true
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: secLangRow; spacing: 4
                    Repeater {
                        model: dualPanel.availableLangs
                        Rectangle {
                            id: secBtnRect
                            property int varCount: dualPanel.getVariantCount("secondary", modelData)
                            property string lang: modelData
                            property bool isSelected: dualPanel.secSecondaryLang === modelData
                            property bool isEmbeddedOnly: dualPanel.opensubLangs.indexOf(modelData) < 0 && dualPanel.findEmbeddedTrack(modelData) !== null
                            width: secLangContent.width + 14; height: 28; radius: 4
                            color: isSelected ? "#4444AA" : "#333355"
                            border.color: isSelected ? "#8888FF" : (isEmbeddedOnly ? "#665544" : "#444466")
                            Row {
                                id: secLangContent
                                anchors.centerIn: parent; spacing: 3
                                Text { id: langText2; text: secBtnRect.lang.toUpperCase() + (secBtnRect.isEmbeddedOnly ? " \uD83D\uDCCE" : ""); color: secBtnRect.isSelected ? "#FFF" : "#AAA"; font.pixelSize: 12; font.bold: secBtnRect.isSelected; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    visible: secBtnRect.isSelected && secBtnRect.varCount > 1
                                    spacing: 2; anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: secBtnRect.varCount
                                        Rectangle {
                                            width: 5; height: 5; radius: 3
                                            color: {
                                                var idx = dualPanel.secondaryVariantIdx[secBtnRect.lang];
                                                return (idx !== undefined && idx === index) ? "#FFFFFF" : "#8888AA";
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (secBtnRect.lang !== dualPanel.secSecondaryLang) dualPanel.searchLanguages(secBtnRect.lang); }
                                onPressAndHold: {
                                    if (secBtnRect.varCount > 1) {
                                        variantPopup.role = "secondary";
                                        variantPopup.lang = secBtnRect.lang;
                                        variantPopup.variants = dualPanel.secondaryVariants[secBtnRect.lang];
                                        variantPopup.currentIdx = dualPanel.secondaryVariantIdx[secBtnRect.lang] || 0;
                                        var globalPos = secBtnRect.mapToItem(dualPanel, 0, secBtnRect.height);
                                        variantPopup.x = Math.min(Math.max(globalPos.x, 8), dualPanel.width - variantPopup.width - 8);
                                        variantPopup.y = globalPos.y + 4;
                                        variantPopup.visible = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- Letterbox Margins Toggle ---
            Rectangle { width: parent.width; height: 1; color: "#444466" }
            Row {
                spacing: 10; width: parent.width
                Text { text: "Sottotitoli fuori video (letterbox)"; color: "#BBBBBB"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 44; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter
                    color: dualPanel.useMargins ? "#44AA44" : "#555555"
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: "#FFFFFF"
                        x: dualPanel.useMargins ? parent.width - width - 2 : 2
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: dualPanel.useMargins = !dualPanel.useMargins
                    }
                }
            }

            // ════════════════════════════════════════════
            // PRIMARY TRACK SETTINGS
            // ════════════════════════════════════════════
            Rectangle { width: parent.width; height: 1; color: "#446644" }
            Text { text: "\u25BC Primaria \u2014 Stile"; color: "#88DD88"; font.pixelSize: 13; font.bold: true }

            // --- Primary Font Size ---
            Row {
                spacing: 8
                Text { text: "Dimensione"; color: "#BBBBBB"; font.pixelSize: 12; width: 90; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: priFsMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: priFsMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.priFontSize > 10) { dualPanel.priFontSize -= 2; dualPanel.scheduleReload(); } } }
                }
                Text { text: dualPanel.priFontSize; color: "#FFF"; font.pixelSize: 14; width: 30;
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: priFsPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: priFsPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.priFontSize < 120) { dualPanel.priFontSize += 2; dualPanel.scheduleReload(); } } }
                }
            }

            // --- Primary Font Color ---
            Row {
                spacing: 4
                Text { text: "Colore"; color: "#BBBBBB"; font.pixelSize: 12; width: 48; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["FFFFFF", "FFFF00", "00FF00", "00FFFF", "FF6600", "FF0000", "FF69B4"]
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: "#" + modelData
                        border.color: dualPanel.priColor === modelData ? "#FFFFFF" : "#555555"
                        border.width: dualPanel.priColor === modelData ? 3 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { dualPanel.priColor = modelData; dualPanel.scheduleReload(); } }
                    }
                }
            }

            // --- Primary Border Color + Size ---
            Row {
                spacing: 4
                Text { text: "Bordo"; color: "#BBBBBB"; font.pixelSize: 12; width: 48; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["000000", "FFFFFF", "555555", "000088", "880000"]
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: "#" + modelData
                        border.color: dualPanel.priBorderColor === modelData ? "#FFFF00" : "#777777"
                        border.width: dualPanel.priBorderColor === modelData ? 3 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { dualPanel.priBorderColor = modelData; dualPanel.scheduleReload(); } }
                    }
                }
                Text { text: "|"; color: "#444466"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: priBsMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { id: priBsMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.priBorderSize > 0) { dualPanel.priBorderSize--; dualPanel.scheduleReload(); } } }
                }
                Text { text: dualPanel.priBorderSize; color: "#FFF"; font.pixelSize: 13; width: 14;
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: priBsPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { id: priBsPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.priBorderSize < 6) { dualPanel.priBorderSize++; dualPanel.scheduleReload(); } } }
                }
            }

            // --- Primary Bold + Position ---
            Row {
                spacing: 6
                Rectangle {
                    width: 50; height: 26; radius: 4
                    color: dualPanel.priBold ? "#44AA44" : "#333355"
                    border.color: dualPanel.priBold ? "#66CC66" : "#444466"
                    Text { text: "B"; color: "#FFF"; font.pixelSize: 13; font.bold: true; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.priBold = !dualPanel.priBold; dualPanel.scheduleReload(); } }
                }
                Rectangle {
                    width: 60; height: 26; radius: 4
                    color: !dualPanel.priPositionTop ? "#44AA44" : "#333355"
                    border.color: !dualPanel.priPositionTop ? "#66CC66" : "#444466"
                    Text { text: "\u2193 Basso"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.priPositionTop = false; dualPanel.scheduleReload(); } }
                }
                Rectangle {
                    width: 55; height: 26; radius: 4
                    color: dualPanel.priPositionTop ? "#44AA44" : "#333355"
                    border.color: dualPanel.priPositionTop ? "#66CC66" : "#444466"
                    Text { text: "\u2191 Alto"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.priPositionTop = true; dualPanel.scheduleReload(); } }
                }
            }

            // --- Primary Delay ---
            Row {
                spacing: 6
                Text { text: "Ritardo"; color: "#BBBBBB"; font.pixelSize: 12; width: 52; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: priDelMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: priDelMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dualPanel.priDelay = Math.round((dualPanel.priDelay - 0.1) * 10) / 10;
                            mpv.setProperty("sub-delay", "" + dualPanel.priDelay);
                        }
                    }
                }
                Text {
                    text: (dualPanel.priDelay >= 0 ? "+" : "") + dualPanel.priDelay.toFixed(1) + "s"
                    color: "#FFF"; font.pixelSize: 13; width: 48
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: priDelPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: priDelPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dualPanel.priDelay = Math.round((dualPanel.priDelay + 0.1) * 10) / 10;
                            mpv.setProperty("sub-delay", "" + dualPanel.priDelay);
                        }
                    }
                }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: priDelReset.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u21BA"; color: "#FFF"; font.pixelSize: 13; anchors.centerIn: parent }
                    MouseArea { id: priDelReset; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.priDelay = 0.0; mpv.setProperty("sub-delay", "0"); }
                    }
                }
            }

            // ════════════════════════════════════════════
            // SECONDARY TRACK SETTINGS
            // ════════════════════════════════════════════
            Rectangle { width: parent.width; height: 1; color: "#444488" }
            Text { text: "\u25BC Secondaria \u2014 Stile"; color: "#8888DD"; font.pixelSize: 13; font.bold: true }

            // --- Secondary Font Size ---
            Row {
                spacing: 8
                Text { text: "Dimensione"; color: "#BBBBBB"; font.pixelSize: 12; width: 90; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: fsMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: fsMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.secFontSize > 10) { dualPanel.secFontSize -= 2; dualPanel.scheduleReload(); } } }
                }
                Text { text: dualPanel.secFontSize; color: "#FFF"; font.pixelSize: 14; width: 30;
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: fsPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: fsPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.secFontSize < 120) { dualPanel.secFontSize += 2; dualPanel.scheduleReload(); } } }
                }
            }

            // --- Secondary Font Color ---
            Row {
                spacing: 4
                Text { text: "Colore"; color: "#BBBBBB"; font.pixelSize: 12; width: 48; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["FFFF00", "FFFFFF", "00FF00", "00FFFF", "FF6600", "FF0000", "FF69B4"]
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: "#" + modelData
                        border.color: dualPanel.secColor === modelData ? "#FFFFFF" : "#555555"
                        border.width: dualPanel.secColor === modelData ? 3 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { dualPanel.secColor = modelData; dualPanel.scheduleReload(); } }
                    }
                }
            }

            // --- Secondary Border Color + Size ---
            Row {
                spacing: 4
                Text { text: "Bordo"; color: "#BBBBBB"; font.pixelSize: 12; width: 48; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["000000", "FFFFFF", "555555", "000088", "880000"]
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: "#" + modelData
                        border.color: dualPanel.secBorderColor === modelData ? "#FFFF00" : "#777777"
                        border.width: dualPanel.secBorderColor === modelData ? 3 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { dualPanel.secBorderColor = modelData; dualPanel.scheduleReload(); } }
                    }
                }
                Text { text: "|"; color: "#444466"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: bsMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { id: bsMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.secBorderSize > 0) { dualPanel.secBorderSize--; dualPanel.scheduleReload(); } } }
                }
                Text { text: dualPanel.secBorderSize; color: "#FFF"; font.pixelSize: 13; width: 14;
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: bsPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { id: bsPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (dualPanel.secBorderSize < 6) { dualPanel.secBorderSize++; dualPanel.scheduleReload(); } } }
                }
            }

            // --- Secondary Bold + Position ---
            Row {
                spacing: 6
                Rectangle {
                    width: 50; height: 26; radius: 4
                    color: dualPanel.secBold ? "#4444AA" : "#333355"
                    border.color: dualPanel.secBold ? "#6666CC" : "#444466"
                    Text { text: "B"; color: "#FFF"; font.pixelSize: 13; font.bold: true; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.secBold = !dualPanel.secBold; dualPanel.scheduleReload(); } }
                }
                Rectangle {
                    width: 60; height: 26; radius: 4
                    color: !dualPanel.secPositionTop ? "#4444AA" : "#333355"
                    border.color: !dualPanel.secPositionTop ? "#6666CC" : "#444466"
                    Text { text: "\u2193 Basso"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.secPositionTop = false; dualPanel.scheduleReload(); } }
                }
                Rectangle {
                    width: 55; height: 26; radius: 4
                    color: dualPanel.secPositionTop ? "#4444AA" : "#333355"
                    border.color: dualPanel.secPositionTop ? "#6666CC" : "#444466"
                    Text { text: "\u2191 Alto"; color: "#FFF"; font.pixelSize: 12; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.secPositionTop = true; dualPanel.scheduleReload(); } }
                }
            }

            // --- Secondary Delay ---
            Row {
                spacing: 6
                Text { text: "Ritardo"; color: "#BBBBBB"; font.pixelSize: 12; width: 52; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: delMinus.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u2212"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: delMinus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dualPanel.secDelay = Math.round((dualPanel.secDelay - 0.1) * 10) / 10;
                            mpv.setProperty("secondary-sub-delay", "" + dualPanel.secDelay);
                        }
                    }
                }
                Text {
                    text: (dualPanel.secDelay >= 0 ? "+" : "") + dualPanel.secDelay.toFixed(1) + "s"
                    color: "#FFF"; font.pixelSize: 13; width: 48
                    horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 28; height: 26; radius: 4; color: delPlus.containsMouse ? "#555577" : "#333355"
                    Text { text: "+"; color: "#FFF"; font.pixelSize: 14; anchors.centerIn: parent }
                    MouseArea { id: delPlus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dualPanel.secDelay = Math.round((dualPanel.secDelay + 0.1) * 10) / 10;
                            mpv.setProperty("secondary-sub-delay", "" + dualPanel.secDelay);
                        }
                    }
                }
                Rectangle {
                    width: 24; height: 26; radius: 4; color: delReset.containsMouse ? "#555577" : "#333355"
                    Text { text: "\u21BA"; color: "#FFF"; font.pixelSize: 13; anchors.centerIn: parent }
                    MouseArea { id: delReset; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { dualPanel.secDelay = 0.0; mpv.setProperty("secondary-sub-delay", "0"); }
                    }
                }
            }
        }
        } // end Flickable

        // --- Variant selection popup (long-press dropdown) ---
        Rectangle {
            id: variantPopup
            visible: false
            width: 270
            height: variantCol.height + 16
            color: "#F0222244"
            border.color: "#7777AA"
            border.width: 1
            radius: 8
            z: 1100

            property string role: ""       // "primary" or "secondary"
            property string lang: ""
            property var variants: []
            property int currentIdx: 0

            // Close on click outside
            MouseArea {
                anchors.fill: parent
                // Absorb clicks inside the popup so they don't close it
                onClicked: {}
            }

            Column {
                id: variantCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: 8
                spacing: 2

                // Header
                Item {
                    width: parent.width; height: 22
                    Text {
                        text: variantPopup.lang.toUpperCase() + " \u2014 " + (variantPopup.variants ? variantPopup.variants.length : 0) + " versioni"
                        color: "#CCCCCC"; font.pixelSize: 12; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "\u2715"; color: vpCloseMa.containsMouse ? "#FFF" : "#888"
                        font.pixelSize: 14; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            id: vpCloseMa; anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: variantPopup.visible = false
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: "#555577" }

                // Scrollable variant list
                Flickable {
                    width: parent.width
                    height: Math.min(variantListCol.height, 200)
                    contentHeight: variantListCol.height
                    clip: true; flickableDirection: Flickable.VerticalFlick

                    Column {
                        id: variantListCol
                        width: parent.width; spacing: 1

                        Repeater {
                            model: variantPopup.variants ? variantPopup.variants.length : 0
                            Rectangle {
                                width: variantListCol.width; height: 28; radius: 3
                                property bool isCurrent: index === variantPopup.currentIdx
                                color: isCurrent ? (variantPopup.role === "primary" ? "#44AA44" : "#4444AA")
                                     : vpItemMa.containsMouse ? "#444466" : "transparent"

                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                    spacing: 6; anchors.verticalCenter: parent.verticalCenter

                                    // Filled/empty dot
                                    Rectangle {
                                        width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter
                                        color: isCurrent ? "#FFFFFF" : "#666688"
                                    }

                                    Text {
                                        property var v: variantPopup.variants ? variantPopup.variants[index] : null
                                        text: {
                                            if (!v) return "";
                                            // Shorten the title for display
                                            var t = v.title || ("Variant " + (index + 1));
                                            return (index + 1) + ". " + (t.length > 38 ? t.substring(0, 38) + "\u2026" : t);
                                        }
                                        color: isCurrent ? "#FFFFFF" : "#BBBBCC"
                                        font.pixelSize: 11
                                        font.bold: isCurrent
                                        elide: Text.ElideRight
                                        width: parent.width - 22
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: vpItemMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        dualPanel.selectVariant(variantPopup.role, variantPopup.lang, index);
                                        variantPopup.currentIdx = index;
                                        variantPopup.visible = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    //
    // Err dialog
    //
    MessageDialog {
        id: errorDialog
        title: "Stremio - Application Error"
        // onAccepted handler does not work
        //icon: StandardIcon.Critical
        //standardButtons: StandardButton.Ok
    }

    FileDialog {
      id: fileDialog
      folder: shortcuts.home
      onAccepted: {
        var fileProtocol = "file://"
        var onWindows = Qt.platform.os === "windows" ? 1 : 0
        var pathSeparators = ["/", "\\"]
        var files = fileDialog.fileUrls.filter(function(fileUrl) {
          // Ignore network drives and alike
          return fileUrl.startsWith(fileProtocol)
        })
        .map(function(fileUrl) {
          // Send actual path and not file protocol URL
          return decodeURIComponent(fileUrl
            .substring(fileProtocol.length + onWindows))
            .replace(/\//g, pathSeparators[onWindows])
        })
        transport.event("file-selected", {
          files: files,
          title: fileDialog.title,
          selectExisting: fileDialog.selectExisting,
          selectFolder: fileDialog.selectFolder,
          selectMultiple: fileDialog.selectMultiple,
          nameFilters: fileDialog.nameFilters,
          selectedNameFilter: fileDialog.selectedNameFilter,
          data: fileDialog.data
        })
      }
      onRejected: {
        transport.event("file-rejected", {
          title: fileDialog.title,
          selectExisting: fileDialog.selectExisting,
          selectFolder: fileDialog.selectFolder,
          selectMultiple: fileDialog.selectMultiple,
          nameFilters: fileDialog.nameFilters,
          selectedNameFilter: fileDialog.selectedNameFilter,
          data: fileDialog.data
        })
      }
      property var data: {}
    }

    //
    // Binding window -> app events
    //
    onWindowStateChanged: function(state) {
        updatePreviousVisibility();
        transport.event("win-state-changed", { state: state })
    }

    onVisibilityChanged: {
        var enabledAlwaysOnTop = root.visible && root.visibility != Window.FullScreen;
        systemTray.alwaysOnTopEnabled(enabledAlwaysOnTop);
        if (!enabledAlwaysOnTop) {
            root.flags &= ~Qt.WindowStaysOnTopHint;
        }

        updatePreviousVisibility();
        transport.event("win-visibility-changed", { visible: root.visible, visibility: root.visibility,
                            isFullscreen: root.visibility === Window.FullScreen })
    }
    
    property int appState: Qt.application.state;
    onAppStateChanged: {
        // WARNING: we should load the app through https to avoid MITM attacks on the clipboard
        var clipboardUrl
        if (clipboard.text.match(/^(magnet|http|https|file|stremio|ipfs):/)) clipboardUrl = clipboard.text
        transport.event("app-state-changed", { state: appState, clipboard: clipboardUrl })
        
        // WARNING: CAVEAT: this works when you've focused ANOTHER app and then get back to this one
        if (Qt.platform.os === "osx" && appState === Qt.ApplicationActive && !root.visible) {
            root.show()
        }
    }

    onClosing: function(event){
        event.accepted = false
        root.hide()
    }

    //
    // AUTO UPDATER
    //
    signal autoUpdaterErr(var msg, var err);
    signal autoUpdaterRestartTimer();

    // Explanation: when the long timer expires, we schedule the short timer; we do that, 
    // because in case the computer has been asleep for a long time, we want another short timer so we don't check
    // immediately (network not connected yet, etc)
    // we also schedule the short timer if the computer is offline
    Timer {
        id: autoUpdaterLongTimer
        interval: 2 * 60 * 60 * 1000
        running: false
        onTriggered: function() { autoUpdaterShortTimer.restart() }
    }
    Timer {
        id: autoUpdaterShortTimer
        interval: 5 * 60 * 1000
        running: false
        onTriggered: function() { } // empty, set if auto-updater is enabled in initAutoUpdater()
    }

    //
    // On complete handler
    //
    Component.onCompleted: function() {
        console.log('Stremio Shell version: '+Qt.application.version)

        // Kind of hacky way to ensure there are no Qt bindings going on; otherwise when we go to fullscreen
        // Qt tries to restore original window size
        root.height = root.initialHeight
        root.width = root.initialWidth

        // Start streaming server
        var args = Qt.application.arguments
        if (args.indexOf("--development") > -1 && args.indexOf("--streaming-server") === -1) 
            console.log("Skipping launch of streaming server under --development");
        else 
            launchServer();

        // Start DualSubtitles addon server
        launchAddonServer();

        // Handle file opens
        var lastArg = args[1]; // not actually last, but we want to be consistent with what happens when we open
                               // a second instance (main.cpp)
        if (args.length > 1 && !lastArg.match('^--')) onAppOpenMedia(lastArg)

        // Check for updates
        console.info(" **** Completed. Loading Autoupdater ***")
        Autoupdater.initAutoUpdater(autoUpdater, root.autoUpdaterErr, autoUpdaterShortTimer, autoUpdaterLongTimer, autoUpdaterRestartTimer, webView.profile.httpUserAgent);
    }
}
