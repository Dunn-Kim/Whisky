// swiftlint:disable file_length
//
//  BottleSettings.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log
import SemanticVersion

/// Represents a pinned program entry in a bottle's quick-access list.
///
/// Pinned programs appear in a prominent location in the UI for fast access.
/// The pin tracks whether the program is on a removable volume so it can
/// handle disconnected drives gracefully.
public struct PinnedProgram: Codable, Hashable, Equatable {
    /// The display name for the pinned program.
    public var name: String
    /// The URL to the program's executable file.
    public var url: URL?
    /// Whether the program is stored on a removable volume.
    ///
    /// When `true`, the pin remains valid even if the volume is disconnected.
    public var removable: Bool

    /// Creates a new pinned program entry.
    ///
    /// - Parameters:
    ///   - name: The display name for the pin.
    ///   - url: The URL to the program's executable.
    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        do {
            let volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume
            self.removable = try !(volume?.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal ?? false)
        } catch {
            self.removable = false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false
    }
}

/// Basic information about a bottle including its name and pinned programs.
///
/// This struct contains the user-visible metadata for a bottle that isn't
/// related to Wine configuration.
public struct BottleInfo: Codable, Equatable {
    /// The display name of the bottle.
    var name: String = "Bottle"
    /// The list of pinned programs for quick access.
    var pins: [PinnedProgram] = []
    /// URLs of programs that should be hidden from the program list.
    var blocklist: [URL] = []
    /// Programs the user unpinned, which the Start Menu scan must not pin again.
    var unpinnedPrograms: [URL] = []

    /// Creates a new BottleInfo with default values.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
        self.unpinnedPrograms = try container.decodeIfPresent([URL].self, forKey: .unpinnedPrograms) ?? []
    }
}

// swiftlint:disable type_body_length
/// The complete configuration settings for a Wine bottle.
///
/// `BottleSettings` is the main configuration type for a bottle, containing all
/// settings related to Wine, Metal graphics, and performance. It's automatically
/// serialized to a plist file in the bottle directory.
///
/// ## Overview
///
/// Settings are organized into logical groups:
/// - **Info**: Name, pins, and blocklist
/// - **Wine Config**: Windows version, AVX, enhanced sync
/// - **Metal Config**: Metal HUD, validation
/// - **Performance Config**: Shader cache, App Nap, VC++ runtime tracking
///
/// ## Example
///
/// ```swift
/// var settings = BottleSettings()
/// settings.name = "Gaming"
/// settings.windowsVersion = .win10
/// settings.graphicsBackend = .dxmt
/// ```
///
/// ## Topics
///
/// ### Basic Information
/// - ``name``
/// - ``pins``
/// - ``blocklist``
///
/// ### Wine Configuration
/// - ``windowsVersion``
/// - ``wineVersion``
/// - ``avxEnabled``
/// - ``enhancedSync``
///
/// ### Graphics Settings
/// - ``metalHud``
/// - ``metalTrace``
/// - ``metalValidation``
/// - ``sequoiaCompatMode``
///
/// ### Performance
/// - ``shaderCacheEnabled``
/// - ``vcRedistInstalled``
public struct BottleSettings: Codable, Equatable {
    /// The current file format version for settings serialization.
    static let defaultFileVersion = SemanticVersion(1, 0, 0)
    /// The version of the settings file format.
    var fileVersion: SemanticVersion = Self.defaultFileVersion
    /// Basic bottle information (name, pins).
    private var info: BottleInfo
    /// Wine-specific configuration.
    private var wineConfig: BottleWineConfig
    /// Metal graphics settings.
    private var metalConfig: BottleMetalConfig
    /// Performance optimization settings.
    private var performanceConfig: BottlePerformanceConfig
    /// Game launcher compatibility settings.
    private var launcherConfig: BottleLauncherConfig
    /// Controller and input device settings.
    private var inputConfig: BottleInputConfig
    /// Cleanup and clipboard behavior settings.
    private var cleanupConfig: BottleCleanupConfig
    /// Graphics backend selection.
    private var graphicsConfig: BottleGraphicsConfig
    /// Display resolution and virtual desktop settings.
    private var displayConfig: BottleDisplayConfig
    /// Audio driver, latency, and device settings.
    private var audioConfig: BottleAudioConfig
    /// Discord presence and rich presence bridging.
    private var discordConfig: BottleDiscordConfig
    /// User-defined DLL overrides at the bottle level.
    private var customDLLOverrides: [DLLOverrideEntry] = []
    /// Environment variables applied game configurations set for games that
    /// were not in the bottle yet, scoped to their executables. See
    /// ``GameConfigEnvironment``.
    public var gameConfigEnvironments: [GameConfigEnvironment] = []

    /// Creates a new BottleSettings instance with default values.
    public init() {
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.performanceConfig = BottlePerformanceConfig()
        self.launcherConfig = BottleLauncherConfig()
        self.inputConfig = BottleInputConfig()
        self.cleanupConfig = BottleCleanupConfig()
        self.graphicsConfig = BottleGraphicsConfig()
        self.displayConfig = BottleDisplayConfig()
        self.audioConfig = BottleAudioConfig()
        self.discordConfig = BottleDiscordConfig()
        self.customDLLOverrides = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self
            .defaultFileVersion
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container
            .decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container
            .decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.performanceConfig = try container.decodeIfPresent(
            BottlePerformanceConfig.self,
            forKey: .performanceConfig
        ) ?? BottlePerformanceConfig()
        self.launcherConfig = try container.decodeIfPresent(
            BottleLauncherConfig.self,
            forKey: .launcherConfig
        ) ?? BottleLauncherConfig()
        self.inputConfig = try container.decodeIfPresent(
            BottleInputConfig.self,
            forKey: .inputConfig
        ) ?? BottleInputConfig()
        self.cleanupConfig = try container.decodeIfPresent(
            BottleCleanupConfig.self,
            forKey: .cleanupConfig
        ) ?? BottleCleanupConfig()
        self.graphicsConfig = try container.decodeIfPresent(
            BottleGraphicsConfig.self,
            forKey: .graphicsConfig
        ) ?? BottleGraphicsConfig()
        self.displayConfig = try container.decodeIfPresent(
            BottleDisplayConfig.self,
            forKey: .displayConfig
        ) ?? BottleDisplayConfig()
        self.audioConfig = try container.decodeIfPresent(
            BottleAudioConfig.self,
            forKey: .audioConfig
        ) ?? BottleAudioConfig()
        self.discordConfig = try container.decodeIfPresent(
            BottleDiscordConfig.self,
            forKey: .discordConfig
        ) ?? BottleDiscordConfig()
        self.customDLLOverrides = try container.decodeIfPresent(
            [DLLOverrideEntry].self,
            forKey: .customDLLOverrides
        ) ?? []
        self.gameConfigEnvironments = try container.decodeIfPresent(
            [GameConfigEnvironment].self,
            forKey: .gameConfigEnvironments
        ) ?? []
    }

    /// The display name of this bottle.
    public var name: String {
        get { info.name }
        set { info.name = newValue }
    }

    /// The Wine version used when this bottle was created.
    ///
    /// This is automatically updated when Wine is upgraded.
    public var wineVersion: SemanticVersion {
        get { wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The Windows version that Wine emulates for this bottle.
    ///
    /// Different Windows versions may provide better compatibility
    /// for different applications. Windows 10 is recommended for most games.
    public var windowsVersion: WinVersion {
        get { wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    /// Whether AVX instruction set support is advertised to programs.
    ///
    /// Enable this via Rosetta 2 for programs that require AVX instructions.
    /// Only applicable on Apple Silicon Macs.
    public var avxEnabled: Bool {
        get { wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The list of pinned programs for quick access.
    public var pins: [PinnedProgram] {
        get { info.pins }
        set { info.pins = newValue }
    }

    /// URLs of programs that should be hidden from the program list.
    ///
    /// Use this to hide unwanted executables like installers or utilities.
    public var blocklist: [URL] {
        get { info.blocklist }
        set { info.blocklist = newValue }
    }

    /// Programs the user unpinned by hand.
    ///
    /// The Start Menu scan runs every time a bottle screen opens and after
    /// every launch, so without a record of the decision an unpin was undone
    /// within seconds. Pinning the program again clears its entry. See
    /// ``startMenuPinsToAdd(candidates:)``.
    public var unpinnedPrograms: [URL] {
        get { info.unpinnedPrograms }
        set { info.unpinnedPrograms = newValue }
    }

    /// The synchronization mode for Wine.
    ///
    /// Enhanced sync modes (ESync/MSync) can improve performance for some applications
    /// by using more efficient synchronization primitives.
    public var enhancedSync: EnhancedSync {
        get { wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    /// Whether to display the Metal performance HUD overlay.
    ///
    /// Shows frame rate and GPU statistics during gameplay.
    public var metalHud: Bool {
        get { metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    /// Whether to enable Metal GPU trace capture.
    ///
    /// Useful for debugging graphics issues with Xcode's GPU debugger. Sets
    /// `MTL_CAPTURE_ENABLED` and the older `METAL_CAPTURE_ENABLED`; under DXMT
    /// the launch also names the executable in `DXMT_CAPTURE_EXECUTABLE`,
    /// without which DXMT captures nothing.
    public var metalTrace: Bool {
        get { metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    /// Whether Metal validation layer is enabled.
    ///
    /// Useful for debugging but impacts performance. Keep disabled
    /// for normal gameplay.
    public var metalValidation: Bool {
        get { metalConfig.metalValidation }
        set { metalConfig.metalValidation = newValue }
    }

    /// Whether macOS Sequoia (15.x) compatibility mode is enabled.
    ///
    /// Applies additional fixes for graphics and launcher issues
    /// specific to macOS 15.x. Enable if experiencing problems.
    public var sequoiaCompatMode: Bool {
        get { metalConfig.sequoiaCompatMode }
        set { metalConfig.sequoiaCompatMode = newValue }
    }

    /// The graphics backend for this bottle.
    ///
    /// Controls which translation layer is used for Direct3D rendering.
    /// `.recommended` resolves to a concrete backend at launch time.
    public var graphicsBackend: GraphicsBackend {
        get { graphicsConfig.backend }
        set { graphicsConfig.backend = newValue }
    }

    /// Whether Whisky publishes the program this bottle launched to Discord.
    ///
    /// Announces every program, including the ones with no Discord support of
    /// their own, but announces them as Whisky. Independent of
    /// ``discordBridge``, which carries a game's own presence instead.
    public var discordPresence: Bool {
        get { discordConfig.presence }
        set { discordConfig.presence = newValue }
    }

    /// Whether games in this bottle may reach the host's Discord client.
    ///
    /// Serves the named pipe a Windows game expects and relays it to Discord,
    /// so a game that publishes rich presence arrives with its own artwork and
    /// state. A game that publishes nothing is unaffected.
    public var discordBridge: Bool {
        get { discordConfig.bridge }
        set { discordConfig.bridge = newValue }
    }

    /// The cap on how many frames a game may present per second.
    ///
    /// Only backends with a limiter honour this -- see
    /// ``GraphicsBackend/supportsFrameRateLimit``.
    public var frameRateLimit: FrameRateLimit {
        get { graphicsConfig.frameRateLimit }
        set { graphicsConfig.frameRateLimit = newValue }
    }

    /// Whether DXMT upscales its swapchain with MetalFX; see
    /// ``BottleGraphicsConfig/dxmtMetalFXUpscale``.
    public var dxmtMetalFXUpscale: Bool {
        get { graphicsConfig.dxmtMetalFXUpscale }
        set { graphicsConfig.dxmtMetalFXUpscale = newValue }
    }

    // MARK: - Audio settings

    /// The audio driver mode for this bottle.
    ///
    /// Controls which audio driver Wine uses. `.auto` lets Wine choose
    /// the best driver (CoreAudio on macOS). Audio driver configuration
    /// is applied via the Wine registry, not environment variables.
    public var audioDriver: AudioDriverMode {
        get { audioConfig.audioDriver }
        set { audioConfig.audioDriver = newValue }
    }

    /// The audio latency preset for this bottle.
    ///
    /// Controls the DirectSound `HelBuflen` buffer size. Larger buffers
    /// improve stability with Bluetooth and USB audio at the cost of
    /// increased latency. Applied via the Wine registry.
    public var audioLatencyPreset: AudioLatencyPreset {
        get { audioConfig.latencyPreset }
        set { audioConfig.latencyPreset = newValue }
    }

    /// The output device routing mode for this bottle.
    ///
    /// Controls whether Wine follows the macOS default output device
    /// or is pinned to the device named by ``pinnedDeviceUID``.
    public var outputDeviceMode: OutputDeviceMode {
        get { audioConfig.outputDeviceMode }
        set { audioConfig.outputDeviceMode = newValue }
    }

    /// The display name of the pinned audio output device, if any.
    ///
    /// Kept only so the settings can still name the device while it is
    /// disconnected; Wine matches on ``pinnedDeviceUID``.
    public var pinnedDeviceName: String? {
        get { audioConfig.pinnedDeviceName }
        set { audioConfig.pinnedDeviceName = newValue }
    }

    /// The CoreAudio UID of the pinned audio output device, if any.
    ///
    /// Only meaningful when ``outputDeviceMode`` is `.pinned`. This is the
    /// identifier Wine's CoreAudio driver matches when picking the default
    /// output; `nil` leaves Wine on the macOS default output.
    public var pinnedDeviceUID: String? {
        get { audioConfig.pinnedDeviceUID }
        set { audioConfig.pinnedDeviceUID = newValue }
    }

    // MARK: - Display settings

    /// Whether Wine's virtual desktop mode is enabled for this bottle.
    ///
    /// When enabled, Wine runs in a windowed virtual desktop instead of
    /// directly managing individual windows. The resolution is controlled
    /// by ``resolutionPreset`` and ``customResolutionWidth``/``customResolutionHeight``.
    public var virtualDesktopEnabled: Bool {
        get { displayConfig.virtualDesktopEnabled }
        set { displayConfig.virtualDesktopEnabled = newValue }
    }

    /// The display resolution preset for the virtual desktop.
    ///
    /// Controls the virtual desktop resolution when ``virtualDesktopEnabled`` is `true`.
    /// Use `.custom` to specify arbitrary dimensions via ``customResolutionWidth``
    /// and ``customResolutionHeight``.
    public var resolutionPreset: ResolutionPreset {
        get { displayConfig.resolutionPreset }
        set { displayConfig.resolutionPreset = newValue }
    }

    /// The custom virtual desktop width in pixels.
    ///
    /// Only used when ``resolutionPreset`` is `.custom`.
    public var customResolutionWidth: Int {
        get { displayConfig.customWidth }
        set { displayConfig.customWidth = newValue }
    }

    /// The custom virtual desktop height in pixels.
    ///
    /// Only used when ``resolutionPreset`` is `.custom`.
    public var customResolutionHeight: Int {
        get { displayConfig.customHeight }
        set { displayConfig.customHeight = newValue }
    }

    // MARK: - Performance settings

    /// Whether shader caching is enabled.
    ///
    /// Shader caching reduces stuttering after the first run
    /// by storing compiled shaders on disk.
    public var shaderCacheEnabled: Bool {
        get { performanceConfig.shaderCacheEnabled }
        set { performanceConfig.shaderCacheEnabled = newValue }
    }

    /// Whether Visual C++ Redistributable is installed in this bottle.
    ///
    /// Track this to avoid redundant installation prompts.
    public var vcRedistInstalled: Bool {
        get { performanceConfig.vcRedistInstalled }
        set { performanceConfig.vcRedistInstalled = newValue }
    }

    /// Whether App Nap should be disabled for Wine processes.
    ///
    /// When enabled, prevents macOS from throttling Wine processes
    /// when the application is in the background, improving game performance.
    public var disableAppNap: Bool {
        get { performanceConfig.disableAppNap }
        set { performanceConfig.disableAppNap = newValue }
    }

    // MARK: - Launcher compatibility settings

    /// Whether launcher compatibility mode is enabled.
    ///
    /// When enabled, applies launcher-specific optimizations for Steam,
    /// Rockstar, EA App, Epic Games, and other platforms (frankea/Whisky#41).
    public var launcherCompatibilityMode: Bool {
        get { launcherConfig.compatibilityMode }
        set { launcherConfig.compatibilityMode = newValue }
    }

    /// The launcher detection mode (auto or manual).
    ///
    /// - **Auto**: Detects launcher from executable path automatically
    /// - **Manual**: Uses explicitly selected launcher type
    public var launcherMode: LauncherMode {
        get { launcherConfig.launcherMode }
        set { launcherConfig.launcherMode = newValue }
    }

    /// Manually selected or auto-detected launcher type.
    ///
    /// Used when `launcherCompatibilityMode` is enabled to apply
    /// launcher-specific environment variables and settings.
    public var detectedLauncher: LauncherType? {
        get { launcherConfig.detectedLauncher }
        set { launcherConfig.detectedLauncher = newValue }
    }

    /// Locale override for launcher compatibility.
    ///
    /// Auto keeps the launcher preset's locale (US English for EA App, Epic
    /// Games, Battle.net, and Rockstar) or the Mac's when the preset sets none,
    /// as Steam's does (#330). Any other choice wins over the preset.
    public var launcherLocale: Locales {
        get { launcherConfig.launcherLocale }
        set { launcherConfig.launcherLocale = newValue }
    }

    /// Whether to enable GPU spoofing for launcher compatibility.
    ///
    /// Reports high-end GPU capabilities to pass launcher checks.
    /// Fixes EA App black screen and "GPU not supported" errors.
    public var gpuSpoofing: Bool {
        get { launcherConfig.gpuSpoofing }
        set { launcherConfig.gpuSpoofing = newValue }
    }

    /// GPU vendor to spoof when GPU spoofing is enabled.
    ///
    /// NVIDIA (default) provides best compatibility across launchers.
    public var gpuVendor: GPUVendor {
        get { launcherConfig.gpuVendor }
        set { launcherConfig.gpuVendor = newValue }
    }

    /// The last ``LauncherLocaleMigration`` this bottle has been through.
    var launcherLocaleMigration: Int {
        get { launcherConfig.localeMigration }
        set { launcherConfig.localeMigration = newValue }
    }

    // MARK: - Controller and input settings

    /// Whether controller compatibility mode is enabled.
    ///
    /// When enabled, applies workarounds for common controller detection
    /// and mapping issues on macOS (frankea/Whisky#42).
    public var controllerCompatibilityMode: Bool {
        get { inputConfig.controllerCompatibilityMode }
        set { inputConfig.controllerCompatibilityMode = newValue }
    }

    /// Whether to disable HIDAPI for joystick input.
    ///
    /// Forces SDL to use alternative backends which may improve
    /// detection for some controllers.
    public var disableHIDAPI: Bool {
        get { inputConfig.disableHIDAPI }
        set { inputConfig.disableHIDAPI = newValue }
    }

    /// Whether to allow joystick events when app is in background.
    ///
    /// Enables controller input even when Wine window doesn't have focus.
    public var allowBackgroundEvents: Bool {
        get { inputConfig.allowBackgroundEvents }
        set { inputConfig.allowBackgroundEvents = newValue }
    }

    /// Whether to disable SDL to XInput mapping conversion.
    ///
    /// May help PlayStation and Switch controllers show correct button mappings.
    public var disableControllerMapping: Bool {
        get { inputConfig.disableControllerMapping }
        set { inputConfig.disableControllerMapping = newValue }
    }

    /// Whether to use native button labels instead of XInput layout.
    ///
    /// When true, sets `SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1` so physical
    /// button positions are used instead of XInput logical layout.
    public var useButtonLabels: Bool {
        get { inputConfig.useButtonLabels }
        set { inputConfig.useButtonLabels = newValue }
    }

    /// Whether the macOS Command key is mapped to Windows Ctrl inside Wine.
    ///
    /// When true, Wine's Mac driver registry receives `LeftCommandIsCtrl=Y`
    /// and `RightCommandIsCtrl=Y` so common shortcuts (Cmd+A/C/V/S) register
    /// inside Wine apps as their Windows equivalents.
    public var commandActsAsControl: Bool {
        get { inputConfig.commandActsAsControl }
        set { inputConfig.commandActsAsControl = newValue }
    }

    // MARK: - Custom DLL overrides

    /// User-defined DLL overrides for this bottle.
    ///
    /// These overrides are composed with managed overrides (from launcher
    /// presets) by ``DLLOverrideResolver``. Bottle custom overrides
    /// take precedence over managed overrides per-DLL.
    public var dllOverrides: [DLLOverrideEntry] {
        get { customDLLOverrides }
        set { customDLLOverrides = newValue }
    }

    // MARK: - Cleanup and clipboard settings

    /// The clipboard handling policy for this bottle.
    ///
    /// Controls how clipboard content is checked before launching Wine programs.
    /// See ``ClipboardPolicy`` for available options.
    public var clipboardPolicy: ClipboardPolicy {
        get { cleanupConfig.clipboardPolicy }
        set { cleanupConfig.clipboardPolicy = newValue }
    }

    /// The size threshold in bytes for considering clipboard content "large".
    ///
    /// Content above this threshold triggers the configured clipboard policy.
    /// Defaults to ``ClipboardManager/largeContentThreshold`` (10 KB).
    public var clipboardThreshold: Int {
        get { cleanupConfig.clipboardThreshold }
        set { cleanupConfig.clipboardThreshold = newValue }
    }

    /// The kill-on-quit policy for Wine processes in this bottle.
    ///
    /// Overrides the global `killOnTerminate` setting on a per-bottle basis.
    /// See ``KillOnQuitPolicy`` for available options.
    public var killOnQuit: KillOnQuitPolicy {
        get { cleanupConfig.killOnQuit }
        set { cleanupConfig.killOnQuit = newValue }
    }

    /// The policy for handling running processes when navigating away from this bottle.
    ///
    /// Controls whether processes Whisky launched keep running, are stopped, or
    /// prompt a confirmation dialog when the user selects a different bottle or
    /// returns to the library while they are still running. Defaults to keeping
    /// them running. See ``CloseWithProcessesPolicy`` for available options.
    public var closeWithProcessesPolicy: CloseWithProcessesPolicy {
        get { cleanupConfig.closeWithProcessesPolicy }
        set { cleanupConfig.closeWithProcessesPolicy = newValue }
    }

    /// Loads bottle settings from a metadata plist file.
    ///
    /// This method handles version migration and validation. If the settings
    /// file doesn't exist or has an incompatible version, default settings
    /// are created.
    ///
    /// - Parameter metadataURL: The URL to the Metadata.plist file.
    /// - Returns: The loaded or newly created settings.
    /// - Throws: An error if the file cannot be read or decoded.
    @discardableResult
    public static func decode(from metadataURL: URL) throws -> BottleSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            // File doesn't exist - create default settings and save them
            let settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        // File exists - read and decode it
        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(BottleSettings.self, from: data)

        guard settings.fileVersion == BottleSettings.defaultFileVersion else {
            Logger.wineKit.warning("Invalid file version `\(settings.fileVersion, privacy: .public)`")
            // Preserve the original before defaults overwrite it, so an unexpected file version
            // (which may carry recoverable user data) is not silently destroyed.
            quarantineCorruptedFile(at: metadataURL)
            settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    /// Saves the settings to a plist file.
    ///
    /// - Parameter metadataUrl: The URL where settings should be saved.
    /// - Throws: An error if the settings cannot be encoded or written.
    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        // Atomic so a crash mid-write can't leave a truncated Metadata.plist behind.
        try data.write(to: metadataUrl, options: .atomic)
    }

    /// Moves an unreadable settings file aside before defaults overwrite it, preserving the
    /// original for diagnosis instead of destroying it (silent data loss).
    ///
    /// The file is renamed to a `<filename>.corrupt-<timestamp>-<nonce>` sibling. The move is
    /// best-effort: if the file does not exist there is nothing to preserve, and if the move
    /// itself fails the error is logged and the caller proceeds to write defaults anyway.
    ///
    /// - Parameter metadataURL: The URL of the settings file to quarantine.
    static func quarantineCorruptedFile(at metadataURL: URL) {
        let fileManager = FileManager.default
        // Only quarantine when there is actually a file to preserve.
        guard fileManager.fileExists(atPath: metadataURL.path(percentEncoded: false)) else { return }

        // Filename-safe timestamp (no colons/spaces): e.g. 2026-06-10T14-30-05Z.
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        let rawTimestamp = formatter.string(from: Date())
        let timestamp = rawTimestamp.replacingOccurrences(of: ":", with: "-")
        // Short random suffix so two quarantines within the same second can't collide
        // (moveItem refuses to overwrite an existing destination, losing the second file).
        let nonce = UUID().uuidString.prefix(8)
        let quarantineURL = metadataURL
            .deletingLastPathComponent()
            .appending(path: "\(metadataURL.lastPathComponent).corrupt-\(timestamp)-\(nonce)")

        do {
            try fileManager.moveItem(at: metadataURL, to: quarantineURL)
            Logger.wineKit.error(
                """
                Quarantined unreadable settings file `\(metadataURL.path(percentEncoded: false), privacy: .public)` \
                to `\(quarantineURL.path(percentEncoded: false), privacy: .public)` before writing defaults
                """
            )
        } catch {
            Logger.wineKit.error(
                """
                Failed to quarantine unreadable settings file \
                `\(metadataURL.path(percentEncoded: false), privacy: .public)`: \
                \(String(describing: error), privacy: .public); proceeding to write defaults
                """
            )
        }
    }

    // MARK: - EnvironmentBuilder Layer Populators

    // swiftlint:disable cyclomatic_complexity

    /// Populates the ``EnvironmentLayer/bottleManaged`` layer with settings-derived env vars.
    ///
    /// This method replaces the direct dict mutation in the deprecated ``environmentVariables(wineEnv:)``.
    ///
    /// - Parameters:
    ///   - builder: The environment builder to populate.
    ///   - resolvedBackend: The concrete backend to use when the bottle is set to
    ///     `.recommended`. Defaults to `nil`, which resolves via
    ///     ``GraphicsBackendResolver`` and therefore depends on the machine's
    ///     installed runtime — tests pin an explicit value so the suite answers
    ///     the same everywhere.
    public func populateBottleManagedLayer(
        builder: inout EnvironmentBuilder,
        resolvedBackend: GraphicsBackend? = nil,
        displayRefreshRate: Int? = nil
    ) {
        // Resolve the graphics backend (`.recommended` -> concrete backend)
        let resolvedBackend = if graphicsBackend == .recommended {
            resolvedBackend ?? GraphicsBackendResolver.resolve()
        } else {
            graphicsBackend
        }

        // The runtime picks the graphics layer itself; only what DXMT reads is set here.
        if resolvedBackend == .dxmt, dxmtMetalFXUpscale {
            builder.set(
                "DXMT_METALFX_SPATIAL_SWAPCHAIN", "1", layer: .bottleManaged,
                reason: "MetalFX spatial upscaling of the DXMT swapchain"
            )
        }

        // Frame rate cap. Rendering past the display's refresh rate produces
        // frames that are discarded before they are shown, so the work only
        // burns power -- an uncapped game pins the GPU at its maximum clock.
        if let fps = frameRateLimit.resolved(displayRefreshRate: displayRefreshRate) {
            for (key, value) in resolvedBackend.frameRateLimitEnvironment(fps: fps) {
                builder.set(
                    key, value, layer: .bottleManaged,
                    reason: "Frame rate limited to \(fps) FPS"
                )
            }
        }

        // Enhanced sync mode
        switch enhancedSync {
        case .none:
            // On macOS 15.4+, WINEESYNC is required for stability
            if MacOSVersion.current < .sequoia15_4 {
                builder.remove("WINEESYNC", layer: .bottleManaged)
                builder.remove("WINEMSYNC", layer: .bottleManaged)
            } else {
                // Ensure a stable default on newer macOS versions:
                // enable ESYNC and clear any conflicting MSYNC setting.
                builder.set("WINEESYNC", "1", layer: .bottleManaged)
                builder.remove("WINEMSYNC", layer: .bottleManaged)
            }
        case .esync:
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
        case .msync:
            builder.set("WINEMSYNC", "1", layer: .bottleManaged)
            // D3DM detects ESYNC and changes behaviour accordingly
            // so we have to lie to it so that it doesn't break
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
        }

        if metalHud {
            builder.set("MTL_HUD_ENABLED", "1", layer: .bottleManaged)
        }

        // MTL_CAPTURE_ENABLED is the name Apple documents for capturing outside
        // Xcode and the one DXMT checks; Metal.framework still reads the older
        // METAL_CAPTURE_ENABLED as well. DXMT also needs the executable named,
        // which only the launch knows (`Wine.dxmtCaptureExecutable`).
        if metalTrace {
            builder.set("MTL_CAPTURE_ENABLED", "1", layer: .bottleManaged)
            builder.set("METAL_CAPTURE_ENABLED", "1", layer: .bottleManaged)
        }

        if avxEnabled {
            builder.set("ROSETTA_ADVERTISE_AVX", "1", layer: .bottleManaged)
        }

        // Metal validation - useful for debugging but can impact performance
        if metalValidation {
            builder.set("MTL_DEBUG_LAYER", "1", layer: .bottleManaged)
        }

        // The old sequoiaCompatMode block is gone: of the three values it set,
        // MTL_DEBUG_LAYER and WINEFSYNC are platform-layer fixes on every
        // supported macOS and the third value is read by no runtime, so the
        // toggle's off position changed nothing and its on position only hid
        // the provenance.

        // Shader cache control: DXMT skips its cache only for "0".
        if !shaderCacheEnabled {
            builder.set("DXMT_SHADER_CACHE", "0", layer: .bottleManaged)
        }
    }

    // swiftlint:enable cyclomatic_complexity

    /// Populates the ``EnvironmentLayer/launcherManaged`` layer with launcher compatibility fixes.
    ///
    /// This method implements the dual-mode launcher compatibility system from frankea/Whisky#41:
    /// - Merges launcher-specific environment overrides
    /// - Applies the bottle's explicit Locale Override over any preset locale
    /// - Configures GPU spoofing for launcher checks
    ///
    /// - Parameters:
    ///   - builder: The environment builder to populate.
    public func populateLauncherManagedLayer(builder: inout EnvironmentBuilder) {
        guard launcherCompatibilityMode else { return }

        // Apply launcher-specific environment overrides if launcher detected
        if let launcher = detectedLauncher {
            for detail in launcher.fixDetails() {
                builder.set(detail.key, detail.value, layer: .launcherManaged, reason: detail.reason)
            }
        }

        // An explicit Locale Override replaces the preset's locale. Some presets
        // set LC_ALL to en_US for the launchers' web views, but every game a
        // launcher starts inherits it, and a game that takes its region or
        // language from the Windows locale needs the user's choice (#330).
        // Auto keeps the preset's value, or the Mac's when there is none.
        // The rawValue check keeps LC_ALL/LANG from ever being set to "".
        if launcherLocale != .auto, !launcherLocale.rawValue.isEmpty {
            // The reason replaces the preset's, which would otherwise stay
            // attached to the overridden value in provenance.
            let reason = "Set by the bottle's Locale Override"
            builder.set("LC_ALL", launcherLocale.rawValue, layer: .launcherManaged, reason: reason)
            builder.set("LANG", launcherLocale.rawValue, layer: .launcherManaged, reason: reason)
            // Force C locale for date/time parsing to avoid ICU issues
            builder.set("LC_TIME", "C", layer: .launcherManaged)
            builder.set("LC_NUMERIC", "C", layer: .launcherManaged)
        }

        // Apply GPU spoofing if enabled
        if gpuSpoofing {
            let gpuEnv = GPUDetection.spoofWithVendor(gpuVendor)
            let launcherEnv = detectedLauncher?.environmentOverrides() ?? [:]
            // Don't override values already set by launcher preset (original behavior:
            // merge with "current.isEmpty ? new : current")
            for (key, value) in gpuEnv {
                let existing = launcherEnv[key]
                if existing == nil || (existing?.isEmpty ?? true) {
                    builder.set(key, value, layer: .launcherManaged)
                }
            }
        }

        // The connection-pooling and SSL variables that used to be set here
        // (WINE_MAX_CONNECTIONS_PER_SERVER and friends) exist in no Wine or
        // WineCX source; nothing ever read them.
    }

    /// Populates the ``EnvironmentLayer/bottleManaged`` layer with controller/input compatibility fixes.
    ///
    /// Sets SDL environment variables to improve gamepad detection and functionality.
    /// See: https://wiki.libsdl.org/SDL2/CategoryHints (applies to both SDL2 and SDL3)
    ///
    /// - Parameter builder: The environment builder to populate.
    public func populateInputCompatibilityLayer(builder: inout EnvironmentBuilder) {
        guard controllerCompatibilityMode else { return }

        // Disable HIDAPI - forces SDL to use alternative input backend
        // May improve detection for controllers that don't work with HIDAPI
        if disableHIDAPI {
            builder.set("SDL_JOYSTICK_HIDAPI", "0", layer: .bottleManaged)
        }

        // Allow joystick events when app is in background
        // Useful for controller input when Wine window loses focus
        if allowBackgroundEvents {
            builder.set("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1", layer: .bottleManaged)
        }

        // Disable SDL to XInput mapping conversion
        // PlayStation/Switch controllers may show correct button mappings without this
        // Both disableControllerMapping (legacy) and useButtonLabels (controller panel) control this hint.
        if disableControllerMapping || useButtonLabels {
            builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "1", layer: .bottleManaged)
        } else {
            builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "0", layer: .bottleManaged)
        }
    }

    /// Populates the audio layer of the environment builder.
    ///
    /// Audio configuration in Wine is **registry-backed**, not environment-variable-backed.
    /// The audio driver (`HKCU\Software\Wine\Drivers\Audio`) and DirectSound buffer size
    /// (`HKCU\Software\Wine\DirectSound\HelBuflen`) are applied via ``WineAudioRegistry``
    /// methods, not through this layer populator.
    ///
    /// This method exists as the EnvironmentBuilder integration point for audio settings,
    /// following the pattern of ``populateInputCompatibilityLayer(builder:)``. It is reserved
    /// for future audio-related environment variables (e.g., `WINEDEBUG` channels for audio
    /// debugging).
    ///
    /// - Parameter builder: The environment builder to populate.
    public func populateAudioLayer(builder: inout EnvironmentBuilder) {
        // Audio settings are applied via Wine registry (WineAudioRegistry), not env vars.
        // This placeholder ensures the EnvironmentBuilder cascade has an audio integration
        // point for future audio-related environment variables.
    }

    // MARK: - Deprecated Environment Variable API

    /// Populates a Wine environment dictionary based on these settings.
    ///
    /// - Parameter wineEnv: The environment dictionary to populate.
    ///   Existing values may be modified or removed based on settings.
    @available(*, deprecated, message: "Use EnvironmentBuilder layer populators instead")
    public func environmentVariables(wineEnv: inout [String: String]) {
        var builder = EnvironmentBuilder()

        // Call layer populators
        populateBottleManagedLayer(builder: &builder)
        populateLauncherManagedLayer(builder: &builder)
        populateInputCompatibilityLayer(builder: &builder)

        // Resolve and merge
        let (resolved, _) = builder.resolve()

        // Handle explicit key removals that the builder encoded as nil entries.
        // Since resolve() omits removed keys, we must also remove them from the caller's dict.
        if enhancedSync == .none, MacOSVersion.current < .sequoia15_4 {
            wineEnv.removeValue(forKey: "WINEESYNC")
            wineEnv.removeValue(forKey: "WINEMSYNC")
        }

        // Merge resolved values into caller's dict (new values overwrite existing)
        wineEnv.merge(resolved) { _, new in new }

        // Compose WINEDLLOVERRIDES via DLLOverrideResolver
        let resolver = DLLOverrideResolver(
            managed: [],
            bottleCustom: dllOverrides,
            programCustom: []
        )
        let (overrideString, _) = resolver.resolve()
        if !overrideString.isEmpty {
            wineEnv["WINEDLLOVERRIDES"] = overrideString
        }
    }
}

// swiftlint:enable type_body_length
