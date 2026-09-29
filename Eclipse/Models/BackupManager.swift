//
//  BackupManager.swift
//  Eclipse
//
//  Created by Soupy-dev on 05/01/2026.
//

import CoreData
import Darwin
import Foundation
import UIKit
#if canImport(CryptoKit)
import CryptoKit

private extension KeyedDecodingContainer {
    /// `contains` also returns true for explicit `null`. Restore authority must
    /// require a payload that actually decoded, while still accepting an
    /// explicit empty collection as authoritative.
    func decodePresence<Value: Decodable>(
        of type: Value.Type,
        forKey key: Key
    ) -> Bool {
        (try? decodeIfPresent(type, forKey: key)) != nil
    }
}

private func decodeBackupJSONValue<Value: Decodable>(
    _ type: Value.Type,
    from value: Any?,
    using decoder: JSONDecoder
) -> Value? {
    guard let value,
          !(value is NSNull),
          JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value) else {
        return nil
    }
    return try? decoder.decode(type, from: data)
}
#endif

struct BackupProfileSnapshot: Codable {
    var id: UUID
    var name: String
    var avatarSymbol: String
    var avatarColorHex: String
    var avatarPhotoData: Data?
    var isKidsProfile: Bool
    var createdAt: Date

    var pinHash: String? = nil

    var pinChangedAt: Date? = nil
    var kidsFlagChangedAt: Date? = nil

    var collections: [BackupCollection] = []
    var progressData: ProgressData = ProgressData()
    var trackerState: TrackerState = TrackerState()
    var catalogs: [Catalog] = []
    var userRatings: [String: Double] = [:]
    var userRatingNotes: [String: String] = [:]
    var searchHistory: BackupSearchHistory = BackupSearchHistory()

    var progressWasCaptured: Bool = true
    var ratingsWereCaptured: Bool = true
    var collectionsWereCaptured: Bool = true
    var catalogsWereCaptured: Bool = true
    var trackerStateWasCaptured: Bool = true
    var trackerCredentialsAndRosterWereCaptured: Bool = false

    var mangaCollectionsWereCaptured: Bool = true
    var mangaReadingProgressWasCaptured: Bool = true
    var mangaCatalogsWereCaptured: Bool = true
    var customCatalogsWereCaptured: Bool = true

    var mangaCollections: [BackupMangaCollection] = []
    var mangaReadingProgress: [String: MangaProgress] = [:]
    var mangaCatalogs: [MangaCatalog] = []
    var customCatalogs: [KanzenCustomCatalog] = []

    var settings: [String: Data] = [:]

    var services: [BackupService]? = nil
    var stremioAddons: [BackupStremioAddon]? = nil
    var skyStream: SkyStreamBackupSnapshot? = nil
    var nuvioPlugins: NuvioStoredPluginsState? = nil

    var readerExtensionsState: BackupReaderExtensionState? = nil
    var readerPrivateCloudConfigurationData: Data? = nil

    // Decode-only compatibility for backups written before Reader Extensions.
    var aidokuState: BackupAidokuState? = nil

    var skyStreamStateData: Data? = nil

    var servicesSettings: [String: Data] = [:]
    var servicesSettingsWereCaptured: Bool = false
}

extension BackupProfileSnapshot {
    enum CodingKeys: String, CodingKey {
        case id, name, avatarSymbol, avatarColorHex, avatarPhotoData, isKidsProfile, createdAt, pinHash
        case pinChangedAt, kidsFlagChangedAt
        case collections, progressData, trackerState, catalogs, userRatings, userRatingNotes, searchHistory
        case progressWasCaptured, ratingsWereCaptured, collectionsWereCaptured, catalogsWereCaptured
        case trackerStateWasCaptured, trackerCredentialsAndRosterWereCaptured
        case mangaCollectionsWereCaptured, mangaReadingProgressWasCaptured, mangaCatalogsWereCaptured
        case customCatalogsWereCaptured
        case mangaCollections, mangaReadingProgress, mangaCatalogs
        case customCatalogs
        case settings
        case services, stremioAddons, skyStream, nuvioPlugins
        case readerExtensionsState, readerPrivateCloudConfigurationData
        case aidokuState, skyStreamStateData, servicesSettings
        case servicesSettingsWereCaptured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),

            avatarSymbol: try container.decodeIfPresent(String.self, forKey: .avatarSymbol)
                ?? ProfileAvatar.defaultSymbol,
            avatarColorHex: try container.decodeIfPresent(String.self, forKey: .avatarColorHex)
                ?? ProfileAvatar.defaultColorHex,
            avatarPhotoData: try container.decodeIfPresent(Data.self, forKey: .avatarPhotoData),
            isKidsProfile: try container.decodeIfPresent(Bool.self, forKey: .isKidsProfile) ?? false,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0),
            pinHash: try container.decodeIfPresent(String.self, forKey: .pinHash),
            pinChangedAt: try container.decodeIfPresent(Date.self, forKey: .pinChangedAt),
            kidsFlagChangedAt: try container.decodeIfPresent(Date.self, forKey: .kidsFlagChangedAt)
        )
        let decodedCollections = try container.decodeIfPresent(
            [BackupCollection].self,
            forKey: .collections
        )
        let decodedProgress = try container.decodeIfPresent(
            ProgressData.self,
            forKey: .progressData
        )
        let decodedTrackerState = try container.decodeIfPresent(
            TrackerState.self,
            forKey: .trackerState
        )
        let decodedCatalogs = try container.decodeIfPresent(
            [Catalog].self,
            forKey: .catalogs
        )
        let decodedRatings = try container.decodeIfPresent(
            [String: Double].self,
            forKey: .userRatings
        )
        let decodedRatingNotes = try container.decodeIfPresent(
            [String: String].self,
            forKey: .userRatingNotes
        )

        collections = BackupData.sanitizedCollections(decodedCollections ?? [])
        progressData = BackupData.sanitizedProgressData(decodedProgress ?? ProgressData())
        trackerState = decodedTrackerState ?? TrackerState()
        catalogs = decodedCatalogs ?? []
        userRatings = BackupData.sanitizedUserRatings(decodedRatings ?? [:])
        userRatingNotes = BackupData.sanitizedUserRatingNotes(decodedRatingNotes ?? [:])
        searchHistory = try container.decodeIfPresent(BackupSearchHistory.self, forKey: .searchHistory)
            ?? BackupSearchHistory()
        let decodedMangaCollections = try container.decodeIfPresent(
            [BackupMangaCollection].self,
            forKey: .mangaCollections
        )
        let decodedMangaReadingProgress = try container.decodeIfPresent(
            [String: MangaProgress].self,
            forKey: .mangaReadingProgress
        )
        let decodedMangaCatalogs = try container.decodeIfPresent(
            [MangaCatalog].self,
            forKey: .mangaCatalogs
        )
        let decodedCustomCatalogs = try container.decodeIfPresent(
            [KanzenCustomCatalog].self,
            forKey: .customCatalogs
        )

        // A capture flag cannot turn an omitted (or explicit null) payload into
        // authoritative empty state. Older profile snapshots did not write the
        // flags, so a present payload remains the backwards-compatible signal
        // that the domain was captured. Ratings and notes are restored as one
        // transaction and therefore require both halves of the pair.
        progressWasCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .progressWasCaptured),
            flagIsPresent: container.contains(.progressWasCaptured),
            payloadIsPresent: decodedProgress != nil
        )
        ratingsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .ratingsWereCaptured),
            flagIsPresent: container.contains(.ratingsWereCaptured),
            payloadIsPresent: decodedRatings != nil && decodedRatingNotes != nil
        )
        collectionsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .collectionsWereCaptured),
            flagIsPresent: container.contains(.collectionsWereCaptured),
            payloadIsPresent: decodedCollections != nil
        )
        catalogsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .catalogsWereCaptured),
            flagIsPresent: container.contains(.catalogsWereCaptured),
            payloadIsPresent: decodedCatalogs != nil
        )
        trackerStateWasCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .trackerStateWasCaptured),
            flagIsPresent: container.contains(.trackerStateWasCaptured),
            payloadIsPresent: decodedTrackerState != nil
        )
        let decodedTrackerCredentialsAndRosterWereCaptured = try container.decodeIfPresent(
            Bool.self,
            forKey: .trackerCredentialsAndRosterWereCaptured
        ) ?? false
        trackerCredentialsAndRosterWereCaptured = trackerStateWasCaptured
            && decodedTrackerCredentialsAndRosterWereCaptured
        mangaCollectionsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .mangaCollectionsWereCaptured),
            flagIsPresent: container.contains(.mangaCollectionsWereCaptured),
            payloadIsPresent: decodedMangaCollections != nil
        )
        mangaReadingProgressWasCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .mangaReadingProgressWasCaptured),
            flagIsPresent: container.contains(.mangaReadingProgressWasCaptured),
            payloadIsPresent: decodedMangaReadingProgress != nil
        )
        mangaCatalogsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .mangaCatalogsWereCaptured),
            flagIsPresent: container.contains(.mangaCatalogsWereCaptured),
            payloadIsPresent: decodedMangaCatalogs != nil
        )
        customCatalogsWereCaptured = Self.domainWasCaptured(
            explicitFlag: try container.decodeIfPresent(Bool.self, forKey: .customCatalogsWereCaptured),
            flagIsPresent: container.contains(.customCatalogsWereCaptured),
            payloadIsPresent: decodedCustomCatalogs != nil
        )
        mangaCollections = decodedMangaCollections ?? []
        mangaReadingProgress = decodedMangaReadingProgress ?? [:]
        mangaCatalogs = decodedMangaCatalogs ?? []
        customCatalogs = decodedCustomCatalogs ?? []
        settings = try container.decodeIfPresent([String: Data].self, forKey: .settings) ?? [:]
        services = try container.decodeIfPresent([BackupService].self, forKey: .services)
        stremioAddons = try container.decodeIfPresent([BackupStremioAddon].self, forKey: .stremioAddons)
        skyStream = try container.decodeIfPresent(SkyStreamBackupSnapshot.self, forKey: .skyStream)
        nuvioPlugins = try container.decodeIfPresent(NuvioStoredPluginsState.self, forKey: .nuvioPlugins)
        aidokuState = try container.decodeIfPresent(BackupAidokuState.self, forKey: .aidokuState)
            .map(BackupData.aidokuStateWithoutExecutablePayloads)
        readerExtensionsState = try container.decodeIfPresent(
            BackupReaderExtensionState.self,
            forKey: .readerExtensionsState
        ) ?? aidokuState.map(BackupReaderExtensionState.migratingLegacyAidoku)
        readerPrivateCloudConfigurationData = Self.boundedReaderPrivateCloudConfigurationData(
            try? container.decodeIfPresent(
                Data.self,
                forKey: .readerPrivateCloudConfigurationData
            )
        )
        skyStreamStateData = try container.decodeIfPresent(Data.self, forKey: .skyStreamStateData)
        let decodedServicesSettings = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .servicesSettings
        ) ?? [:]
        let safeServicesSettings = BackupData.servicesSettingsForExperimentalCloudSync(
            decodedServicesSettings
        )
        servicesSettings = safeServicesSettings ?? [:]
        servicesSettingsWereCaptured = (
            try container.decodeIfPresent(Bool.self, forKey: .servicesSettingsWereCaptured)
                ?? false
        ) && safeServicesSettings != nil
    }

    private static func domainWasCaptured(
        explicitFlag: Bool?,
        flagIsPresent: Bool,
        payloadIsPresent: Bool
    ) -> Bool {
        payloadIsPresent && (!flagIsPresent || explicitFlag == true)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(avatarSymbol, forKey: .avatarSymbol)
        try container.encode(avatarColorHex, forKey: .avatarColorHex)
        try container.encodeIfPresent(avatarPhotoData, forKey: .avatarPhotoData)
        try container.encode(isKidsProfile, forKey: .isKidsProfile)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(pinHash, forKey: .pinHash)
        try container.encodeIfPresent(pinChangedAt, forKey: .pinChangedAt)
        try container.encodeIfPresent(kidsFlagChangedAt, forKey: .kidsFlagChangedAt)
        try container.encode(BackupData.sanitizedCollections(collections), forKey: .collections)
        try container.encode(BackupData.sanitizedProgressData(progressData), forKey: .progressData)
        try container.encode(trackerState, forKey: .trackerState)
        try container.encode(catalogs, forKey: .catalogs)
        try container.encode(BackupData.sanitizedUserRatings(userRatings), forKey: .userRatings)
        try container.encode(BackupData.sanitizedUserRatingNotes(userRatingNotes), forKey: .userRatingNotes)
        try container.encode(searchHistory, forKey: .searchHistory)
        try container.encode(progressWasCaptured, forKey: .progressWasCaptured)
        try container.encode(ratingsWereCaptured, forKey: .ratingsWereCaptured)
        try container.encode(collectionsWereCaptured, forKey: .collectionsWereCaptured)
        try container.encode(catalogsWereCaptured, forKey: .catalogsWereCaptured)
        try container.encode(trackerStateWasCaptured, forKey: .trackerStateWasCaptured)
        try container.encode(
            trackerStateWasCaptured && trackerCredentialsAndRosterWereCaptured,
            forKey: .trackerCredentialsAndRosterWereCaptured
        )
        try container.encode(mangaCollectionsWereCaptured, forKey: .mangaCollectionsWereCaptured)
        try container.encode(mangaReadingProgressWasCaptured, forKey: .mangaReadingProgressWasCaptured)
        try container.encode(mangaCatalogsWereCaptured, forKey: .mangaCatalogsWereCaptured)
        try container.encode(customCatalogsWereCaptured, forKey: .customCatalogsWereCaptured)
        try container.encode(mangaCollections, forKey: .mangaCollections)
        try container.encode(mangaReadingProgress, forKey: .mangaReadingProgress)
        try container.encode(mangaCatalogs, forKey: .mangaCatalogs)
        try container.encode(customCatalogs, forKey: .customCatalogs)
        try container.encode(settings, forKey: .settings)
        try container.encodeIfPresent(services, forKey: .services)
        try container.encodeIfPresent(stremioAddons, forKey: .stremioAddons)
        try container.encodeIfPresent(skyStream, forKey: .skyStream)
        try container.encodeIfPresent(nuvioPlugins, forKey: .nuvioPlugins)
        try container.encodeIfPresent(readerExtensionsState?.sanitized(), forKey: .readerExtensionsState)
        try container.encodeIfPresent(
            Self.boundedReaderPrivateCloudConfigurationData(
                readerPrivateCloudConfigurationData
            ),
            forKey: .readerPrivateCloudConfigurationData
        )
        try container.encodeIfPresent(skyStreamStateData, forKey: .skyStreamStateData)
        let safeServicesSettings = BackupData.servicesSettingsForExperimentalCloudSync(
            servicesSettings
        )
        try container.encode(safeServicesSettings ?? [:], forKey: .servicesSettings)
        try container.encode(
            servicesSettingsWereCaptured && safeServicesSettings != nil,
            forKey: .servicesSettingsWereCaptured
        )
    }

    static let maximumReaderPrivateCloudConfigurationBytes = 8 * 1_024 * 1_024

    static func boundedReaderPrivateCloudConfigurationData(_ data: Data?) -> Data? {
        guard let data,
              !data.isEmpty,
              data.count <= maximumReaderPrivateCloudConfigurationBytes else {
            return nil
        }
        return data
    }
}

struct BackupData: Codable {
    static let currentCloudSchemaVersion = "2.0"

    let version: String
    let createdDate: Date

    var servicesSettings: [String: Data]? = nil
    var servicesSettingsWereCaptured: Bool = false

    var sharesServices: Bool? = nil

    var profiles: [BackupProfileSnapshot]? = nil

    var skyStreamSharedPayloads: [BackupSkyStreamSharedPayload]? = nil
    var nuvioSharedPayloads: [BackupNuvioSharedPayload]? = nil

    var activeProfileID: UUID? = nil

    var accentColor: Data?
    var settingsGradientColor: Data?
    var readerAccentColor: Data?
    var tmdbLanguage: String
    var selectedAppearance: String
    var readerSelectedAppearance: String
    var readerGlobalAppearanceEnabled: Bool
    var readerSettingsGradientColor: Data?
    var enableSubtitlesByDefault: Bool
    var defaultSubtitleLanguage: String
    var playerSubtitleAppearanceEnabled: Bool

    var preferredAutoAudioLanguage: String
    var preferredAnimeAudioLanguage: String
    var inAppPlayer: String
    var showScheduleTab: Bool
    var showLocalScheduleTime: Bool
    var defaultScheduleMode: String = ScheduleMode.anime.rawValue
    var scheduleWindowDays: Int = ScheduleWindow.defaultValue.rawValue

    var localNotificationSubscriptions: String?
    var localNotificationEpisodeReminders: String?
    var localNotificationEpisodeLeadTime: Int?
    var localNotificationSeasonLeadTime: Int?
    var localNotificationIncludeAnimeSpecials: Bool?

    var defaultPlaybackSpeed: Double = 1.0
    var holdSpeedPlayer: Double = 2.0
    var externalPlayer: String = "none"
    var preferDownloadedMedia: Bool = false
    var alwaysLandscape: Bool = false
    var playerPlaybackLockEnabled: Bool = PlayerPlaybackLockSettings.defaultEnabled
    var aniSkipEnabled: Bool = true
    var introDBEnabled: Bool = true
    var introDBAppEnabled: Bool = true
    var aniSkipAutoSkip: Bool = false
    var skip85sEnabled: Bool = false
    var skip85sAlwaysVisible: Bool = false
    var showNextEpisodeButton: Bool = true
    var showEpisodeBrowserButton: Bool = true
    var showPlayerServicesButton: Bool = false
    var showNextEpisodePosterButton: Bool = false
    var nextEpisodeThreshold: Double = 0.90
    var nextEpisodeSkipFillerEnabled: Bool = NextEpisodeFillerSettings.defaultEnabled
    var playerBrightnessGestureEnabled: Bool = false
    var playerVolumeGestureEnabled: Bool = false
    var playerTwoFingerTapPlayPauseEnabled: Bool = true
    var playerCenterTapPlayPauseEnabled: Bool = true
    var playerDoubleTapSeekEnabled: Bool = true
    var playerDoubleTapSeekSeconds: Double = 10.0
    var playerOpenSubtitlesEnabled: Bool = false
    var playerOpenSubtitlesAutoFallbackEnabled: Bool = true
    var playerPerformanceOverlayEnabled: Bool = false
    var mpvForegroundFPS: Int = 30
    var mpvRenderBackend: String = MPVRenderBackend.defaultBackend.rawValue
    var mpvMetalQualityProfile: String = MPVMetalQualityProfile.defaultProfile.rawValue
    var mpvUpscalingMode: String = MPVUpscalingMode.defaultMode.rawValue
    var mpvNeuralUpscaler: String = MPVNeuralUpscaler.defaultUpscaler.rawValue
    var mpvNeuralUpscalerTV: String = MPVNeuralUpscaler.defaultUpscaler.rawValue
    var mpvPlayerSkin: String = MPVPlayerSkin.defaultSkin.rawValue
    var mpvPlayerSkinCustomPrimaryColor: Data?
    var mpvPlayerSkinCustomSecondaryColor: Data?
    var mpvPlayerSkinAnimationsEnabled: Bool = MPVPlayerSkinSettings.defaultAnimationsEnabled
    var mpvPlayerSkinTintControlsOnly: Bool = MPVPlayerSkinSettings.defaultTintControlsOnly
    var mpvPictureInPictureEnabled: Bool = true
    var mpvAppExitPictureInPictureEnabled: Bool = false
    var mpvHDRMode: String = MPVHDRMode.defaultMode.rawValue
    var mpvSurroundSoundEnabled: Bool = true
    var watchTogetherEnabled: Bool = WatchTogetherSettings.defaultEnabled
    var smartInAppPlayerChoosingEnabled: Bool = false
    var experimentalFeaturesEnabled: Bool?
    var experimentalFeaturesLastChangedAt: Double?
    var experimentalMPVPreloadEnabled: Bool = true
    var experimentalMPVSmoothTransitionEnabled: Bool = true
    var experimentalMPVPreloadCellularEnabled: Bool = false
    var experimentalMPVPreloadWifiLimitMB: Int = ExperimentalFeatureState.mpvPreloadWifiDefaultLimitMB
    var experimentalMPVPreloadCellularLimitMB: Int = ExperimentalFeatureState.mpvPreloadCellularDefaultLimitMB
    var experimentalMPVShowRemainingTime: Bool = true
    var experimentalMPVPreciseProgress: Bool = true
    var experimentalMPVIgnoreSpecialSubtitleStyles: Bool = false
    var experimentalMPVPreloadAutoClear: Bool = true
    var experimentalICloudSyncEnabled: Bool = false

    var subtitleForegroundColor: Data?
    var subtitleStrokeColor: Data?
    var subtitleStrokeWidth: Double = 1.0
    var subtitleFontSize: Double = 30.0
    var subtitleVerticalOffset: Double = -6.0
    var subtitlesVisible: Bool = false

    var showKanzen: Bool = false
    var hideSplashScreen: Bool?
    var modeSwitchAnimationEnabled: Bool = ModeSwitchAnimationSettings.defaultEnabled
    var kanzenAutoUpdateModules: Bool = true
    var seasonMenu: Bool = false
    var horizontalEpisodeList: Bool = false
    var mediaDetailTitleArtworkEnabled: Bool = MediaDetailTitleArtworkSettings.defaultEnabled
    var mediaDetailAlternatePosterEnabled: Bool = MediaDetailAlternatePosterSettings.defaultEnabled
    var mediaDetailSimilarTitlesEnabled: Bool = MediaDetailSimilarTitlesSettings.defaultEnabled
    var useClassicScheduleUI: Bool = false
    var heroBannerCatalogId: String = "trending"
    var heroBannerBehavior: String = HeroBannerBehavior.defaultValue.rawValue

    var homeCatalogLayoutOverrides: String = ""
    var homeAnimatedBackgroundEnabled: Bool?
    var homeAnimatedBackgroundQuality: String = HomeAnimatedBackgroundQuality.defaultValue.rawValue
    var homeAnimatedBackgroundFrameRate: String = HomeAnimatedBackgroundFrameRate.defaultValue.rawValue
    var appPerformanceOverlayEnabled: Bool = AppPerformanceOverlaySettings.defaultEnabled
    var experimentalMediaDesignPreset: String = ExperimentalMediaDesignPreset.defaultValue.rawValue
    var experimentalHeroBleedLevel: String = ExperimentalHeroBleedLevel.defaultValue.rawValue
    var experimentalHomeCardShape: String = ExperimentalHomeCardShape.defaultValue.rawValue
    var experimentalMultiGradientPalette: String = ExperimentalMultiGradientPalette.defaultValue.rawValue
    var experimentalHeroHeightScale: Double = ExperimentalVisualTuning.defaultHeroHeightScale
    var experimentalHeroBleedStrength: Double = ExperimentalVisualTuning.defaultHeroBleedStrength
    var experimentalHeroFadeDistanceScale: Double = ExperimentalVisualTuning.defaultHeroFadeDistanceScale
    var experimentalSectionSpacingScale: Double = ExperimentalVisualTuning.defaultSectionSpacingScale
    var experimentalCardRadiusScale: Double = ExperimentalVisualTuning.defaultCardRadiusScale
    var experimentalMediaCardScale: Double = ExperimentalVisualTuning.defaultMediaCardScale
    var experimentalGlassStrength: Double = ExperimentalVisualTuning.defaultGlassStrength
    var experimentalGradientBaseDarkness: Double = ExperimentalVisualTuning.defaultGradientBaseDarkness
    var experimentalGradientAccentIntensity: Double = ExperimentalVisualTuning.defaultGradientAccentIntensity
    var experimentalGradientScrollMotion: Double = ExperimentalVisualTuning.defaultGradientScrollMotion
    var experimentalGradientUseCustomColors: Bool = false
    var experimentalGradientColorA: Data?
    var experimentalGradientColorB: Data?
    var experimentalGradientColorC: Data?
    var atmosphereStyle: String = AtmosphereStyle.gradient.rawValue
    var atmosphereSolidColorSource: String = AtmosphereSolidColorSource.dominant.rawValue
    var atmosphereSolidColor: Data?
    var readerAtmosphereStyle: String = AtmosphereStyle.gradient.rawValue
    var readerAtmosphereSolidColorSource: String = AtmosphereSolidColorSource.dominant.rawValue
    var readerAtmosphereSolidColor: Data?
    var mediaDetailElementOrder: String = MediaDetailElement.defaultOrderRawValue
    var mediaDetailHiddenElements: String = ""
    var readerDetailElementOrder: String = ReaderDetailElement.defaultOrderRawValue
    var readerDetailHiddenElements: String = ""
    var mediaColumnsPortrait: Int = 3
    var mediaColumnsLandscape: Int = 5

    var readingMode: Int = 2
    var kanzenReaderMode: String = "webtoon"
    var kanzenReaderModeOverrides: [String: String] = [:]
    var readerDownsampleImages: Bool = true
    var readerCropBorders: Bool = false
    var readerDisableQuickActions: Bool = false
    var readerDisableDoubleTap: Bool = false
    var readerLiveText: Bool = false
    var readerHideBarsOnSwipe: Bool = false
    var readerBackgroundColor: String = "black"
    var readerOrientation: String = "device"
    var readerTapZones: String = "disabled"
    var readerInvertTapZones: Bool = false
    var readerAnimatePageTransitions: Bool = true
    var readerUpscaleImages: Bool = false
    var readerUpscaleMaxHeight: Int = 2000
    var readerUpscaleModelName: String = "None"
    var readerPagesToPreload: Int = 3
    var readerPagedPageLayout: String = "single"
    var readerPagedPageOffset: Bool = false
    var readerPagedPageOffsetOverrides: [String: Bool] = [:]
    var readerSplitWideImages: Bool = false
    var readerReverseSplitOrder: Bool = false
    var readerVerticalInfiniteScroll: Bool = true
    var readerPillarbox: Bool = false
    var readerPillarboxAmount: Double = 15
    var readerPillarboxOrientation: String = "both"
    var readerOrientationLockEnabled: Bool = false
    var readerOrientationLockMask: String = "all"
    var readerReadThresholdPercent: Double = 80

    var readerFontSize: Double = 16
    var readerFontFamily: String = "-apple-system"
    var readerFontWeight: String = "normal"
    var readerColorPreset: Int = 0
    var readerTextAlignment: String = "left"
    var readerLineSpacing: Double = 1.6
    var readerMargin: Double = 4

    var autoClearCacheEnabled: Bool = false
    var autoClearCacheThresholdMB: Double = 500
    var highQualityThreshold: Double = 0.9
    var backgroundHLSPipelineEnabled: Bool = false
    var readerDownloadsBackgroundEnabled: Bool = true
    var readerDownloadsWifiOnly: Bool = false
    var readerDownloadsParallelLimit: Int = 2
    var autoUpdateServicesEnabled: Bool = true
    var servicesAutoModeEnabled: Bool = AutoModeSettings.defaultEnabled
    var servicesAutoSelectEpisodesEnabled: Bool = false
    var servicesAutoModeErrorIntelligenceEnabled: Bool = AutoModeErrorIntelligenceSettings.defaultEnabled
    var servicesAutoModeSourceIds: [String] = []
    var servicesAutoModeSourceOrderIds: [String] = []
    var servicesAutoModeQualityPreference: String = AutoModeQualityPreference.defaultPreference.rawValue
    var servicesResultMinimumSimilarity: Double = ServicesResultRankingSettings.defaultMinimumSimilarity
    var servicesDropMismatchedResults: Bool = ServicesResultRankingSettings.defaultDropMismatchedResults
    var servicesStremioStyleSheetEnabled: Bool = ServicesSheetPresentationSettings.defaultStremioStyleEnabled
    var servicesIncludedStreamLanguages: [String] = []
    var servicesHiddenStreamLanguages: [String] = []
    var servicesHideStreamsWithoutLanguageData: Bool = false
    var servicesAssumeOriginalAudio: Bool = false
    var servicesTreatDubbedAnimeAsEnglish: Bool = false
    var servicesHiddenStreamQualities: [Int] = []
    var servicesHideStreamsWithoutDetectedQuality: Bool = false

    var servicesExtraRulesSourceIds: [String]? = nil
    var githubReleaseAutoCheckEnabled: Bool = true
    var githubReleaseUpdateAvailable: Bool = false
    var githubReleaseLatestVersion: String = ""
    var githubReleaseURL: String = ""
    var githubReleaseShowAlertPending: Bool = false
    var githubReleaseLastPromptedVersion: String = ""
    var filterHorrorContent: Bool = false
    var selectedSimilarityAlgorithm: String = SimilarityAlgorithm.hybrid.rawValue
    var performanceModeEnabled: Bool = PerformanceModeSettings.defaultEnabled
    var performanceModeSkipAniListTraversalForAnimeDetails: Bool = false
    var performanceModeFastAnimeCatalogOverrides: [String: Bool] = [:]

    var kanzenHomeSelectedSourceID: String = ""
    var kanzenRecentSourceSearches: [String] = []

    var collections: [BackupCollection] = []

    var progressData: ProgressData = ProgressData()

    var trackerState: TrackerState = TrackerState()

    var catalogs: [Catalog] = []

    var services: [BackupService] = []

    var stremioAddons: [BackupStremioAddon]? = nil

    var skyStream: SkyStreamBackupSnapshot? = nil

    var nuvioPlugins: NuvioStoredPluginsState? = nil

    var mangaCollections: [BackupMangaCollection] = []
    var mangaReadingProgress: [String: MangaProgress] = [:]
    var mangaCatalogs: [MangaCatalog] = []
    var customCatalogs: [KanzenCustomCatalog] = []
    var kanzenModules: [BackupKanzenModule] = []
    var readerExtensionsState: BackupReaderExtensionState?

    // Decode-only compatibility. New backups never encode Aidoku metadata or payloads.
    var aidokuState: BackupAidokuState?

    var searchHistory: BackupSearchHistory = BackupSearchHistory()
    var recommendationCache: [TMDBSearchResult] = []

    var userRatings: [String: Double] = [:]
    var userRatingNotes: [String: String] = [:]

    var mediaStateSettings: [String: Data]? = nil

    private(set) var hasMangaCollections = true
    private(set) var hasMangaReadingProgress = true
    private(set) var hasMangaCatalogs = true
    private(set) var hasCustomCatalogs = true
    private(set) var hasKanzenModules = true
    private(set) var hasUserRatings = true
    private(set) var hasCollections = true
    private(set) var hasProgressData = true
    private(set) var hasTrackerState = true
    private(set) var hasCatalogs = true
    private(set) var hasServices = true

    // Top-level scalar settings predate profile snapshots and are still read
    // for legacy backups. Keep per-key decode authority so a syntactically
    // valid but incomplete backup cannot turn omitted/null settings into the
    // decoder defaults and overwrite the destination with them.
    fileprivate(set) var decodedTopLevelSettingKeys: Set<String> = []
    fileprivate(set) var allTopLevelSettingsWereCaptured = true

    func redactedForExperimentalCloudSync(
        stripSkyStreamArchives: Bool = false
    ) -> BackupData {
        var snapshot = self

        snapshot.progressData.movieProgress = progressData.movieProgress.map { entry in
            var redacted = entry
            redacted.lastHref = nil
            redacted.lastContentReference = nil
            return redacted
        }
        snapshot.progressData.episodeProgress = progressData.episodeProgress.map { entry in
            var redacted = entry
            redacted.lastHref = nil
            redacted.lastContentReference = nil
            return redacted
        }

        let safeServices = Self.servicesForExperimentalCloudSync(services)
        let safeStremioAddons = stremioAddons.flatMap(
            Self.stremioAddonsForExperimentalCloudSync
        )
        if let safeServices, let safeStremioAddons {
            snapshot.services = safeServices
            snapshot.stremioAddons = safeStremioAddons
        } else {
            snapshot.services = []
            snapshot.hasServices = false
            snapshot.stremioAddons = nil
        }
        snapshot.skyStream = skyStream.flatMap {
            Self.skyStreamSnapshotForExperimentalCloudSync(
                $0,
                stripArchives: stripSkyStreamArchives
            )
        }

        snapshot.nuvioPlugins = nuvioPlugins.flatMap(Self.nuvioStateForExperimentalCloudSync)

        snapshot.profiles = profiles?.map { profileSnapshot in
            var redacted = profileSnapshot

            let safeServices = profileSnapshot.services.flatMap(
                Self.servicesForExperimentalCloudSync
            )
            let safeAddons = profileSnapshot.stremioAddons.flatMap(
                Self.stremioAddonsForExperimentalCloudSync
            )
            if let safeServices, let safeAddons {
                redacted.services = safeServices
                redacted.stremioAddons = safeAddons
            } else {
                redacted.services = nil
                redacted.stremioAddons = nil
            }
            redacted.nuvioPlugins = profileSnapshot.nuvioPlugins.flatMap(
                Self.nuvioStateForExperimentalCloudSync
            )
            redacted.readerExtensionsState = profileSnapshot.readerExtensionsState?.sanitized()
            redacted.aidokuState = nil
            redacted.skyStream = profileSnapshot.skyStream.flatMap {
                Self.skyStreamSnapshotForExperimentalCloudSync($0, stripArchives: true)
            }
            redacted.skyStreamStateData = nil
            redacted.progressData.movieProgress = profileSnapshot.progressData.movieProgress.map { entry in
                var entryCopy = entry
                entryCopy.lastHref = nil
                entryCopy.lastContentReference = nil
                return entryCopy
            }
            redacted.progressData.episodeProgress = profileSnapshot.progressData.episodeProgress.map { entry in
                var entryCopy = entry
                entryCopy.lastHref = nil
                entryCopy.lastContentReference = nil
                return entryCopy
            }
            return redacted
        }

        let safeKanzenModules = kanzenModules.filter {
            Self.cloudSafeManifestURL($0.moduleurl) != nil
        }
        snapshot.kanzenModules = safeKanzenModules
        snapshot.hasKanzenModules = hasKanzenModules
            && safeKanzenModules.count == kanzenModules.count

        snapshot.readerExtensionsState = readerExtensionsState?.sanitized()
        snapshot.aidokuState = nil

        snapshot.servicesSettings = Self.servicesSettingsForExperimentalCloudSync(servicesSettings)
        snapshot.servicesSettingsWereCaptured = servicesSettingsWereCaptured
            && snapshot.servicesSettings != nil
        snapshot.profiles = snapshot.profiles?.map { profileSnapshot in
            var redacted = profileSnapshot
            let settings = Self.servicesSettingsForExperimentalCloudSync(
                profileSnapshot.servicesSettings
            )
            redacted.servicesSettings = settings ?? [:]
            redacted.servicesSettingsWereCaptured = profileSnapshot.servicesSettingsWereCaptured
                && settings != nil
            return redacted
        }

        snapshot.skyStreamSharedPayloads = nil
        snapshot.nuvioSharedPayloads = nil
        snapshot.readerUpscaleModelName = "None"
        snapshot.experimentalICloudSyncEnabled = false

        snapshot.recommendationCache = []
        return snapshot
    }

    var privateCloudConfigurationWasCapturedCompletely: Bool {
        guard let sharesServices,
              let profiles,
              !profiles.isEmpty,
              let activeProfileID,
              profiles.contains(where: { $0.id == activeProfileID }),
              hasServices,
              stremioAddons != nil,
              servicesSettingsWereCaptured else {
            return false
        }

#if !os(tvOS)
        if PlatformCapabilities.current.supportsReader {
            guard Self.readerExtensionStateWasCapturedCompletely(readerExtensionsState) else {
                return false
            }
        }
#endif

        if PlatformCapabilities.current.supportsSkyStreamPlugins {
            guard let skyStream,
                  SkyStreamPrivateCloudConfigurationPolicy
                    .snapshotHasCompleteConfiguration(skyStream) else {
                return false
            }
        }
        if PlatformCapabilities.current.supportsNuvioPlugins,
           nuvioPlugins == nil {
            return false
        }

        for profile in profiles {
            guard profile.trackerStateWasCaptured,
                  profile.trackerCredentialsAndRosterWereCaptured else {
                return false
            }
#if !os(tvOS)
            if PlatformCapabilities.current.supportsReader {
                guard Self.readerExtensionStateWasCapturedCompletely(
                    profile.readerExtensionsState
                ),
                Self.readerPrivateCloudConfigurationWasCapturedCompletely(
                    profile.readerPrivateCloudConfigurationData,
                    profileID: profile.id
                ) else {
                    return false
                }
            }
#endif
            if !sharesServices {
                guard profile.services != nil,
                      profile.stremioAddons != nil,
                      profile.servicesSettingsWereCaptured else {
                    return false
                }
                if PlatformCapabilities.current.supportsSkyStreamPlugins {
                    guard let skyStream = profile.skyStream,
                          SkyStreamPrivateCloudConfigurationPolicy
                            .snapshotHasCompleteConfiguration(skyStream) else {
                        return false
                    }
                }
                if PlatformCapabilities.current.supportsNuvioPlugins,
                   profile.nuvioPlugins == nil {
                    return false
                }
            }
        }
        return true
    }

#if !os(tvOS)
    private static func readerExtensionStateWasCapturedCompletely(
        _ state: BackupReaderExtensionState?
    ) -> Bool {
        guard let state else { return false }
        return (try? state.runtimeSnapshot()) != nil
    }

    private static func readerPrivateCloudConfigurationWasCapturedCompletely(
        _ data: Data?,
        profileID: UUID
    ) -> Bool {
        guard let data = BackupProfileSnapshot
            .boundedReaderPrivateCloudConfigurationData(data),
              let configuration = try? JSONDecoder().decode(
                ReaderExtensionPrivateCloudConfiguration.self,
                from: data
              ),
              configuration.profileID == profileID,
              (try? ReaderExtensionPrivateCloudConfigurationPolicy.validate(
                configuration
              )) != nil else {
            return false
        }
        return true
    }

    mutating func removeReaderDomainsWithoutCompletePrivateCloudAuthority() {
        guard PlatformCapabilities.current.supportsReader else { return }

        let originalProfiles = profiles
        let activeProfileHasCompleteReaderAuthority = activeProfileID.flatMap { activeID in
            originalProfiles?.first(where: { $0.id == activeID })
        }.map { profile in
            Self.readerExtensionStateWasCapturedCompletely(profile.readerExtensionsState)
                && Self.readerPrivateCloudConfigurationWasCapturedCompletely(
                    profile.readerPrivateCloudConfigurationData,
                    profileID: profile.id
                )
        } == true

        profiles = originalProfiles?.map { profile in
            guard Self.readerExtensionStateWasCapturedCompletely(profile.readerExtensionsState),
                  Self.readerPrivateCloudConfigurationWasCapturedCompletely(
                    profile.readerPrivateCloudConfigurationData,
                    profileID: profile.id
                  ) else {
                var preserved = profile
                preserved.readerExtensionsState = nil
                preserved.readerPrivateCloudConfigurationData = nil
                preserved.aidokuState = nil
                return preserved
            }
            return profile
        }

        guard Self.readerExtensionStateWasCapturedCompletely(readerExtensionsState),
              activeProfileHasCompleteReaderAuthority else {
            readerExtensionsState = nil
            aidokuState = nil
            return
        }
    }
#endif

    fileprivate static let cloudUnsafeServicesSettingsKeys: Set<String> = [
        "nuvioPluginsState.v1",
        "nuvioPluginsState.v2",
        "nuvioMissingCodeRepairCursor.v1",
        "skyStreamPendingSafeCloudSnapshot.v1",
        "lastServiceAutoUpdateTimestamp",
        "kanzenLastModuleAutoUpdate",
        "kanzenAidokuInstalledSources",
        "kanzenAidokuSourceLists",
        "readerExtensions.repositories.v1",
        "readerExtensions.installedSources.v1",
        "readerExtensions.approvedDomains.v1"
    ]

    fileprivate static func isTypedOrLegacyReaderSourceSetting(_ key: String) -> Bool {
        key.hasPrefix("kanzenAidoku") || key.hasPrefix("readerExtensions.")
    }

    fileprivate static func servicesSettingsForExperimentalCloudSync(
        _ settings: [String: Data]?
    ) -> [String: Data]? {
        guard let settings else { return nil }
        guard settings.count <= BackupManager.maximumProfileSettingKeys else { return nil }
        var safe: [String: Data] = [:]
        for (key, data) in settings {
            if cloudUnsafeServicesSettingsKeys.contains(key)
                || isTypedOrLegacyReaderSourceSetting(key) {
                continue
            }
            guard key.utf8.count <= 512,
                  EclipseSettingsRegistry.scope(for: key) == .services,
                  data.count <= BackupManager.maximumProfileSettingValueBytes,
                  BackupManager.validatedBackupSettingValue(
                    from: data,
                    forKey: key
                  ) != nil else {
                return nil
            }
            safe[key] = data
        }
        return safe
    }

    static func servicesForExperimentalCloudSync(
        _ services: [BackupService]
    ) -> [BackupService]? {
        guard services.count <= MediaStateServiceSourcesPayload.maximumServices,
              Set(services.map(\.id)).count == services.count else {
            return nil
        }
        let safe = services.compactMap(serviceForExperimentalCloudSync)
        return safe.count == services.count ? safe : nil
    }

    static func stremioAddonsForExperimentalCloudSync(
        _ addons: [BackupStremioAddon]
    ) -> [BackupStremioAddon]? {
        guard addons.count <= MediaStateServiceSourcesPayload.maximumStremioAddons,
              Set(addons.map(\.id)).count == addons.count else {
            return nil
        }
        let safe = addons.compactMap(stremioAddonForExperimentalCloudSync)
        return safe.count == addons.count ? safe : nil
    }

    fileprivate static func aidokuStateWithoutExecutablePayloads(
        _ incoming: BackupAidokuState
    ) -> BackupAidokuState {
        var state = incoming
        state.installedSources = incoming.installedSources.map { source in
            BackupAidokuInstalledSource(
                id: source.id,
                name: source.name,
                version: source.version,
                languages: source.languages,
                iconPath: source.iconPath,
                externalIconURL: source.externalIconURL,
                contentRatingRawValue: source.contentRatingRawValue,
                sourceListURL: source.sourceListURL,
                packageURL: source.packageURL,
                isEnabled: source.isEnabled,
                order: source.order,
                lastUpdated: source.lastUpdated,
                lastError: source.lastError,
                packageDigest: source.packageDigest,
                payloadArchiveData: nil
            )
        }
        state.sharedPayloads = nil
        return state
    }

    static func nuvioStateForExperimentalCloudSync(
        _ state: NuvioStoredPluginsState
    ) -> NuvioStoredPluginsState? {
        let bounded = NuvioPluginStore.bounded(state)
        guard !bounded.wasBounded,
              bounded.state.repositories.allSatisfy({
                  PrivateCloudSourceURLPolicy.validatedHTTPURLString($0.manifestUrl) != nil
              }),
              bounded.state.scrapers.allSatisfy({
                  PrivateCloudSourceURLPolicy.validatedHTTPURLString($0.repositoryUrl) != nil
              }) else {
            return nil
        }
        return bounded.state
    }

    static func nuvioMetadataForMediaState(
        persistedValue: Any?
    ) -> Data? {
        let state: NuvioStoredPluginsState
        if let persistedValue {
            guard let persistedData = persistedValue as? Data else { return nil }
            guard NuvioPluginStore.persistedStateDataIsWithinLimit(persistedData),
                  let decoded = try? JSONDecoder().decode(
                    NuvioStoredPluginsState.self,
                    from: persistedData
                  ) else {
                return nil
            }
            state = decoded
        } else {
            state = NuvioStoredPluginsState()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let safeState = nuvioStateForExperimentalCloudSync(state),
              let encoded = try? encoder.encode(safeState), !encoded.isEmpty,
           encoded.count <= MediaStateServiceSourcesPayload.maximumNuvioMetadataBytes else {
            return nil
        }
        return encoded
    }

    static func nuvioRestorePlanForExperimentalCloudSync(
        incoming: NuvioStoredPluginsState,
        current: NuvioStoredPluginsState
    ) -> ExperimentalCloudNuvioRestorePlan {
        guard let safeIncoming = nuvioStateForExperimentalCloudSync(incoming),
              let safeCurrent = nuvioStateForExperimentalCloudSync(current) else {
            return ExperimentalCloudNuvioRestorePlan(
                state: current,
                deviceLocalSourceIDs: Set(
                    current.repositories.map(\.id) + current.scrapers.map(\.id)
                )
            )
        }
        let boundedCurrent = safeCurrent
        let safeCurrentRepositoryIDs = Set(safeCurrent.repositories.map(\.id))

        let deviceLocalRepositories = boundedCurrent.repositories.filter {
            !safeCurrentRepositoryIDs.contains($0.id)
        }
        let deviceLocalRepositoryIDs = Set(deviceLocalRepositories.map(\.id))
        let deviceLocalScrapers = boundedCurrent.scrapers.filter {
            deviceLocalRepositoryIDs.contains($0.repositoryId)
        }

        var merged = safeIncoming
        merged.repositories.append(contentsOf: deviceLocalRepositories.filter { repository in
            !merged.repositories.contains(where: { $0.id == repository.id })
        })
        merged.scrapers.append(contentsOf: deviceLocalScrapers.filter { scraper in
            !merged.scrapers.contains(where: { $0.id == scraper.id })
        })

        let survivingScraperIDs = Set(merged.scrapers.map(\.id))
        let incomingScraperIDs = Set(safeIncoming.scrapers.map(\.id))
        let deviceLocalScraperIDs = Set(deviceLocalScrapers.map(\.id))
        merged.scraperSettings = safeIncoming.scraperSettings.filter {
            incomingScraperIDs.contains($0.key)
        }
        for (scraperID, settings) in boundedCurrent.scraperSettings
        where deviceLocalScraperIDs.contains(scraperID)
            && survivingScraperIDs.contains(scraperID) {
            merged.scraperSettings[scraperID] = settings
        }
        merged = NuvioPluginStore.bounded(merged).state

        let mergedRepositoryIDs = Set(merged.repositories.map(\.id))
        let mergedScraperIDs = Set(merged.scrapers.map(\.id))
        let survivingDeviceLocalRepositoryIDs = deviceLocalRepositoryIDs.intersection(
            mergedRepositoryIDs
        )
        let survivingDeviceLocalScraperIDs = Set(deviceLocalScrapers.map(\.id)).intersection(
            mergedScraperIDs
        )
        return ExperimentalCloudNuvioRestorePlan(
            state: merged,
            deviceLocalSourceIDs: survivingDeviceLocalRepositoryIDs.union(
                survivingDeviceLocalScraperIDs
            )
        )
    }

    private static func cloudSafeManifestURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cloudSafeURLString(value) != nil,
              let components = URLComponents(string: trimmed),
              components.fragment == nil else {
            return nil
        }
        return value
    }

    private static func cloudSafeURLString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !containsCloudUnsafeSecretInURL(trimmed),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",

              components.user == nil,
              components.password == nil,
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,

              (components.percentEncodedQuery ?? "").isEmpty,
              !containsCredentialShapedPathSegment(components.percentEncodedPath) else {
            return nil
        }

        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func containsCredentialShapedPathSegment(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        if lowercased.contains("x-amz-") || lowercased.contains("x-goog-") { return true }
        return path.split(separator: "/").contains { $0.hasPrefix("eyJ") }
    }

    private static func containsCloudUnsafeSecretInURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else {
            return containsCloudUnsafeSecret(value)
        }
        if let user = components.user, containsCloudUnsafeSecret(user) { return true }
        if let password = components.password, !password.isEmpty { return true }
        if let query = components.percentEncodedQuery, containsCloudUnsafeSecret(query) { return true }
        if let fragment = components.percentEncodedFragment,
           containsCloudUnsafeSecret(fragment) { return true }
        return components.percentEncodedPath
            .split(separator: "/")
            .contains { $0.contains("=") && containsCloudUnsafeSecret(String($0)) }
    }

    private static func containsCloudUnsafeSecret(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let secretMarkers = [
            "access_token",
            "refresh_token",
            "authorization",
            "bearer ",
            "api_key",
            "apikey",
            "password",
            "passwd",
            "session",
            "secret",
            "token="
        ]
        return secretMarkers.contains { lowercased.contains($0) }
    }

    static func serviceForExperimentalCloudSync(_ service: BackupService) -> BackupService? {
        guard service.jsonMetadata.utf8.count <= 128 * 1_024,
              service.jsScript.utf8.count <= 512 * 1_024,
              let safeURL = PrivateCloudSourceURLPolicy.validatedHTTPURLString(
                service.url
              ) else {
            return nil
        }
        return BackupService(
            id: service.id,
            url: safeURL,
            jsonMetadata: service.jsonMetadata,
            jsScript: service.jsScript,
            isActive: service.isActive,
            sortIndex: service.sortIndex
        )
    }

    static func stremioAddonForExperimentalCloudSync(
        _ addon: BackupStremioAddon
    ) -> BackupStremioAddon? {
        guard addon.manifestJSON.utf8.count <= 256 * 1_024,
              let safeURL = PrivateCloudSourceURLPolicy.validatedHTTPURLString(
                addon.configuredURL
              ) else {
            return nil
        }
        return BackupStremioAddon(
            id: addon.id,
            configuredURL: safeURL,
            manifestJSON: addon.manifestJSON,
            isActive: addon.isActive,
            sortIndex: addon.sortIndex
        )
    }

    static func skyStreamSnapshotForExperimentalCloudSync(
        _ incoming: SkyStreamBackupSnapshot,
        stripArchives: Bool = false
    ) -> SkyStreamBackupSnapshot? {
        let configurationIsComplete = SkyStreamPrivateCloudConfigurationPolicy
            .snapshotHasCompleteConfiguration(incoming)
        guard incoming.privateCloudConfigurationIsComplete != true
                || configurationIsComplete else {
            return nil
        }
        let validatedURL: (String) -> String? = configurationIsComplete
            ? skyStreamPrivateCloudURLString
            : skyStreamCloudSafeURLString

        func resolvedURL(_ rawValue: String, relativeTo baseURL: URL) -> String? {
            guard let resolved = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }
            return validatedURL(resolved.absoluteString)
        }

        func sanitizedPluginManifest(
            _ incomingManifest: SkyStreamPluginManifest,
            relativeTo baseURL: URL? = nil
        ) -> SkyStreamPluginManifest? {
            func configuredURL(_ rawValue: String) -> String? {
                if let baseURL {
                    return resolvedURL(rawValue, relativeTo: baseURL)
                }
                return validatedURL(rawValue)
            }

            var manifest = incomingManifest
            manifest.additionalFields = [:]
            if !manifest.baseURL.isEmpty {
                guard let baseURL = configuredURL(manifest.baseURL) else { return nil }
                manifest.baseURL = baseURL
            }
            if let iconURL = manifest.iconURL {
                guard let validatedIconURL = configuredURL(iconURL) else { return nil }
                manifest.iconURL = validatedIconURL
            }
            if let domains = manifest.domains {
                var sanitizedDomains: [SkyStreamPluginDomain] = []
                sanitizedDomains.reserveCapacity(domains.count)
                for incomingDomain in domains {
                    guard let domainURL = configuredURL(incomingDomain.url) else { return nil }
                    var domain = incomingDomain
                    domain.url = domainURL
                    domain.additionalFields = [:]
                    sanitizedDomains.append(domain)
                }
                manifest.domains = sanitizedDomains
            }
            if let providers = manifest.providers {
                var sanitizedProviders: [SkyStreamPluginProvider] = []
                sanitizedProviders.reserveCapacity(providers.count)
                for incomingProvider in providers {
                    var provider = incomingProvider
                    if let baseURL = provider.baseURL {
                        guard let validatedBaseURL = configuredURL(baseURL) else { return nil }
                        provider.baseURL = validatedBaseURL
                    }
                    if let iconURL = provider.iconURL {
                        guard let validatedIconURL = configuredURL(iconURL) else { return nil }
                        provider.iconURL = validatedIconURL
                    }
                    provider.additionalFields = [:]
                    sanitizedProviders.append(provider)
                }
                manifest.providers = sanitizedProviders
            }
            return manifest
        }

        var repositories: [SkyStreamRepositoryBackupSnapshot] = []
        repositories.reserveCapacity(incoming.repositories.count)
        for repository in incoming.repositories {
            guard let sourceURL = validatedURL(repository.sourceURL),
                  let baseURL = URL(string: sourceURL) else { return nil }
            var sanitized = repository
            sanitized.sourceURL = sourceURL
            sanitized.additionalFields = [:]
            let rawPluginListURLs = sanitized.pluginListURLs.isEmpty
                ? (sanitized.manifest?.pluginLists ?? [])
                : sanitized.pluginListURLs
            var pluginListURLs: [String] = []
            pluginListURLs.reserveCapacity(rawPluginListURLs.count)
            for rawValue in rawPluginListURLs {
                guard let resolved = resolvedURL(rawValue, relativeTo: baseURL) else { return nil }
                pluginListURLs.append(resolved)
            }
            sanitized.pluginListURLs = pluginListURLs
            sanitized.lastRefreshedAt = nil
            sanitized.frozenAt = nil
            guard !sanitized.pluginListURLs.isEmpty else { return nil }
            if var manifest = sanitized.manifest {
                guard sanitized.kind == .repository,
                      SkyStreamRepositoryManifest.isSupportedManifestVersion(
                          manifest.manifestVersion
                      ) else { return nil }
                for rawValue in manifest.pluginLists {
                    guard resolvedURL(rawValue, relativeTo: baseURL) != nil else { return nil }
                }
                manifest.additionalFields = [:]
                manifest.pluginLists = sanitized.pluginListURLs
                var includedRepositories: [String] = []
                includedRepositories.reserveCapacity(manifest.includedRepositories.count)
                for rawValue in manifest.includedRepositories {
                    guard let resolved = resolvedURL(rawValue, relativeTo: baseURL) else { return nil }
                    includedRepositories.append(resolved)
                }
                manifest.includedRepositories = includedRepositories
                var embeddedPlugins: [SkyStreamPluginListEntry] = []
                embeddedPlugins.reserveCapacity(manifest.plugins.count)
                for incomingEntry in manifest.plugins {
                    guard let archiveURL = resolvedURL(incomingEntry.url, relativeTo: baseURL),
                          let embeddedManifest = sanitizedPluginManifest(
                            incomingEntry.manifest,
                            relativeTo: baseURL
                          ) else { return nil }
                    var entry = incomingEntry
                    entry.url = archiveURL
                    entry.manifest = embeddedManifest
                    entry.additionalFields = [:]
                    embeddedPlugins.append(entry)
                }
                manifest.plugins = embeddedPlugins
                if let iconURL = manifest.iconURL {
                    guard let validatedIconURL = resolvedURL(iconURL, relativeTo: baseURL) else {
                        return nil
                    }
                    manifest.iconURL = validatedIconURL
                }
                if let websiteURL = manifest.websiteURL {
                    guard let validatedWebsiteURL = resolvedURL(
                        websiteURL,
                        relativeTo: baseURL
                    ) else { return nil }
                    manifest.websiteURL = validatedWebsiteURL
                }
                sanitized.manifest = manifest
            } else {
                guard sanitized.kind == .pluginList else { return nil }
            }
            guard SkyStreamBackupMetadataPolicy.isBounded(repository: sanitized) else {
                return nil
            }
            repositories.append(sanitized)
        }
        repositories.sort { $0.sourceURL < $1.sourceURL }

        var aggregateArchiveBytes = 0
        var plugins: [SkyStreamPluginBackupSnapshot] = []
        plugins.reserveCapacity(incoming.plugins.count)
        for plugin in incoming.plugins {
            guard let sourceURL = validatedURL(plugin.state.provenance.sourceURL) else {
                return nil
            }
            var sanitized = plugin
            if stripArchives {
                sanitized.archivePayload = nil
                sanitized.payloadWasRedacted = true
            } else if let archive = plugin.archivePayload {
                let digest = SHA256.hash(data: archive)
                    .map { String(format: "%02x", $0) }
                    .joined()
                let (nextAggregateBytes, overflow) = aggregateArchiveBytes.addingReportingOverflow(
                    archive.count
                )
                if archive.count <= 20 * 1_024 * 1_024,
                   digest.caseInsensitiveCompare(plugin.state.archiveSHA256) == .orderedSame,
                   !overflow,
                   nextAggregateBytes <= 64 * 1_024 * 1_024 {
                    aggregateArchiveBytes = nextAggregateBytes
                    sanitized.archivePayload = archive
                    sanitized.payloadWasRedacted = false
                } else {
                    sanitized.archivePayload = nil
                    sanitized.payloadWasRedacted = true
                }
            } else {
                sanitized.archivePayload = nil
                sanitized.payloadWasRedacted = true
            }
            sanitized.additionalFields = [:]
            sanitized.state.additionalFields = [:]
            sanitized.state.payloadRelativePath = ""
            sanitized.state.runtimeStorage = nil
            if configurationIsComplete {
                guard SkyStreamPrivateCloudConfigurationPolicy
                    .preferencesAreCompleteAndBounded(sanitized.state.preferences) else {
                    return nil
                }
            } else {
                sanitized.state.preferences = sanitized.state.preferences.filter { key, value in
                    !value.isSecret &&
                        !value.isRedacted &&
                        !containsCloudUnsafeSecret(key)
                }
            }
            sanitized.state.preferences = sanitized.state.preferences.mapValues { value in
                var canonical = value
                canonical.updatedAt = nil
                return canonical
            }
            sanitized.preferencesWereRedacted = !configurationIsComplete

            sanitized.state.provenance.sourceURL = sourceURL
            if let repositoryURL = sanitized.state.provenance.repositoryURL {
                guard let validatedRepositoryURL = validatedURL(repositoryURL) else { return nil }
                sanitized.state.provenance.repositoryURL = validatedRepositoryURL
            }
            if let pluginListURL = sanitized.state.provenance.pluginListURL {
                guard let validatedPluginListURL = validatedURL(pluginListURL) else { return nil }
                sanitized.state.provenance.pluginListURL = validatedPluginListURL
            }
            sanitized.state.provenance.additionalFields = [:]
            sanitized.state.provenance.pinnedAt = Date(timeIntervalSince1970: 0)
            sanitized.state.provenance.frozenAt = nil
            sanitized.state.provenance.expectedArchiveSHA256 = sanitized.state.archiveSHA256
            if let selectedDomainURL = sanitized.state.selectedDomainURL {
                guard let validatedSelectedDomainURL = validatedURL(selectedDomainURL) else {
                    return nil
                }
                sanitized.state.selectedDomainURL = validatedSelectedDomainURL
            }
            sanitized.state.providers = sanitized.state.providers.filter {
                $0.removedAt == nil
            }.map { provider in
                var provider = provider
                provider.removedAt = nil
                provider.additionalFields = [:]
                return provider
            }.sorted { $0.id < $1.id }

            guard let manifest = sanitizedPluginManifest(sanitized.state.manifest) else {
                return nil
            }
            sanitized.state.manifest = manifest
            sanitized.state.compatibility.reasons = sanitized.state.compatibility.reasons.map { reason in
                var reason = reason
                reason.additionalFields = [:]
                return reason
            }
            sanitized.state.installedAt = Date(timeIntervalSince1970: 0)
            sanitized.state.updatedAt = Date(timeIntervalSince1970: 0)
            sanitized.state.compatibility = .untested
            let usesDynamicProviders = sanitized.state.usesDynamicProviders == true
                || sanitized.state.manifest.providers?.isEmpty == true
            sanitized.state.usesDynamicProviders = usesDynamicProviders
            if usesDynamicProviders {
                sanitized.state.manifest.providers = []
            }
            if let selectedDomainURL = sanitized.state.selectedDomainURL,
               sanitized.state.manifest.domains?.contains(where: {
                    $0.url == selectedDomainURL
               }) != true {
                return nil
            }
            guard SkyStreamBackupMetadataPolicy.isBounded(pluginState: sanitized.state) else {
                return nil
            }
            plugins.append(sanitized)
        }
        plugins.sort { $0.id < $1.id }
        return SkyStreamBackupSnapshot(
            schemaVersion: incoming.schemaVersion,
            repositories: repositories,
            plugins: plugins,
            createdAt: Date(timeIntervalSince1970: 0),
            isSafeCloudSnapshot: true,
            privateCloudConfigurationIsComplete: configurationIsComplete ? true : nil,
            additionalFields: [:]
        )
    }

    private static func skyStreamPrivateCloudURLString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              value == trimmed,
              value.utf8.count <= 8 * 1_024,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.host?.isEmpty == false,
              components.url?.absoluteString == value else {
            return nil
        }
        return value
    }

    private static func skyStreamCloudSafeURLString(_ value: String) -> String? {
        guard let sanitized = cloudSafeURLString(value),
              var components = URLComponents(string: sanitized),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.queryItems?.isEmpty != false else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    static func captureMediaStateSettings(from defaults: UserDefaults? = nil) -> [String: Data] {
        var result: [String: Data] = [:]
        for key in MediaStateSettingRegistry.allKeys {
            let defaults = defaults ?? ProfileSettingsStore.store(for: key)
            guard MediaStateSettingRegistry.scope(for: key)?.appliesToCurrentPlatform == true,
                  let value = defaults.object(forKey: key),
                  PropertyListSerialization.propertyList(value, isValidFor: .binary),
                  let data = try? PropertyListSerialization.data(
                    fromPropertyList: value,
                    format: .binary,
                    options: 0
                  ) else {
                continue
            }
            result[key] = data
        }
        return result
    }

    static func restoreMediaStateSettings(
        _ settings: [String: Data]?,
        to defaults: UserDefaults? = nil,
        appliesProfileScopedWrites: Bool = true,
        appliesServicesScopedWrites: Bool = true
    ) {
        guard let settings else { return }
        for (key, data) in settings {
            switch EclipseSettingsRegistry.scope(for: key) {
            case .profile where !appliesProfileScopedWrites:
                continue
            case .services where !appliesServicesScopedWrites:
                continue
            case .profile, .services, .device:
                break
            }
            let defaults = defaults ?? ProfileSettingsStore.store(for: key)
            guard MediaStateSettingRegistry.scope(for: key)?.appliesToCurrentPlatform == true,
                  let value = MediaStateSettingValueValidator.validatedValue(
                      from: data,
                      forKey: key
                  ) else {
                continue
            }
            defaults.set(value, forKey: key)
        }
    }

    static func mediaStateSettings(fromJSONValue value: Any?) -> [String: Data]? {
        guard let values = value as? [String: Any] else { return nil }
        let decoded = values.reduce(into: [String: Data]()) { result, item in
            guard let base64 = item.value as? String,
                  let data = Data(base64Encoded: base64) else { return }
            result[item.key] = data
        }
        return decoded
    }

    enum CodingKeys: String, CodingKey {
        case version, createdDate
        case accentColor, settingsGradientColor, readerAccentColor, tmdbLanguage, selectedAppearance, readerSelectedAppearance, readerGlobalAppearanceEnabled, readerSettingsGradientColor, enableSubtitlesByDefault, defaultSubtitleLanguage, playerSubtitleAppearanceEnabled, enableVLCSubtitleEditMenu, preferredAutoAudioLanguage, preferredAnimeAudioLanguage, inAppPlayer, playerChoice, showScheduleTab, showLocalScheduleTime, defaultScheduleMode, scheduleWindowDays
        case localNotificationSubscriptions, localNotificationEpisodeReminders, localNotificationEpisodeLeadTime, localNotificationSeasonLeadTime, localNotificationIncludeAnimeSpecials
        case defaultPlaybackSpeed, holdSpeedPlayer, externalPlayer, preferDownloadedMedia, alwaysLandscape, playerPlaybackLockEnabled, aniSkipEnabled, introDBEnabled, introDBAppEnabled, aniSkipAutoSkip, skip85sEnabled, skip85sAlwaysVisible, showNextEpisodeButton, showEpisodeBrowserButton, showVLCEpisodeBrowserButton, showPlayerServicesButton, showNextEpisodePosterButton, nextEpisodeThreshold, nextEpisodeSkipFillerEnabled, vlcHeaderProxyEnabled
        case playerBrightnessGestureEnabled, playerVolumeGestureEnabled, vlcBrightnessGestureEnabled, vlcVolumeGestureEnabled, playerTwoFingerTapPlayPauseEnabled, playerCenterTapPlayPauseEnabled, playerDoubleTapSeekEnabled, vlcDoubleTapSeekEnabled, playerDoubleTapSeekSeconds, vlcDoubleTapSeekSeconds, playerOpenSubtitlesEnabled, vlcOpenSubtitlesEnabled, playerOpenSubtitlesAutoFallbackEnabled, vlcOpenSubtitlesAutoFallbackEnabled, playerPerformanceOverlayEnabled, mpvForegroundFPS, mpvRenderBackend, mpvMetalQualityProfile, mpvUpscalingMode, mpvNeuralUpscaler, mpvNeuralUpscalerTV, mpvPlayerSkin, mpvPlayerSkinCustomPrimaryColor, mpvPlayerSkinCustomSecondaryColor, mpvPlayerSkinAnimationsEnabled, mpvPlayerSkinTintControlsOnly, mpvPictureInPictureEnabled, mpvAppExitPictureInPictureEnabled, mpvHDRMode, mpvSurroundSoundEnabled, watchTogetherEnabled, smartInAppPlayerChoosingEnabled, experimentalFeaturesEnabled, experimentalFeaturesLastChangedAt, experimentalMPVPreloadEnabled, experimentalMPVSmoothTransitionEnabled, experimentalMPVPreloadCellularEnabled, experimentalMPVPreloadWifiLimitMB, experimentalMPVPreloadCellularLimitMB, experimentalMPVShowRemainingTime, experimentalMPVPreciseProgress, experimentalMPVIgnoreSpecialSubtitleStyles, experimentalMPVPreloadAutoClear, experimentalICloudSyncEnabled
        case subtitleForegroundColor, subtitleStrokeColor, subtitleStrokeWidth, subtitleFontSize, subtitleVerticalOffset, subtitlesVisible
        case showKanzen, hideSplashScreen, modeSwitchAnimationEnabled, kanzenAutoUpdateModules, seasonMenu, horizontalEpisodeList, mediaDetailTitleArtworkEnabled, mediaDetailAlternatePosterEnabled, mediaDetailSimilarTitlesEnabled, useClassicScheduleUI, heroBannerCatalogId, heroBannerBehavior, homeCatalogLayoutOverrides, homeAnimatedBackgroundEnabled, homeAnimatedBackgroundQuality, homeAnimatedBackgroundFrameRate, appPerformanceOverlayEnabled, experimentalMediaDesignPreset, experimentalHeroBleedLevel, experimentalHomeCardShape, experimentalMultiGradientPalette, experimentalHeroHeightScale, experimentalHeroBleedStrength, experimentalHeroFadeDistanceScale, experimentalSectionSpacingScale, experimentalCardRadiusScale, experimentalMediaCardScale, experimentalGlassStrength, experimentalGradientBaseDarkness, experimentalGradientAccentIntensity, experimentalGradientScrollMotion, experimentalGradientUseCustomColors, experimentalGradientColorA, experimentalGradientColorB, experimentalGradientColorC, atmosphereStyle, atmosphereSolidColorSource, atmosphereSolidColor, readerAtmosphereStyle, readerAtmosphereSolidColorSource, readerAtmosphereSolidColor, mediaDetailElementOrder, mediaDetailHiddenElements, readerDetailElementOrder, readerDetailHiddenElements, mediaColumnsPortrait, mediaColumnsLandscape
        case readingMode, kanzenReaderMode, kanzenReaderModeOverrides, readerDownsampleImages, readerCropBorders, readerDisableQuickActions, readerDisableDoubleTap, readerLiveText, readerHideBarsOnSwipe, readerBackgroundColor, readerOrientation, readerTapZones, readerInvertTapZones, readerAnimatePageTransitions, readerUpscaleImages, readerUpscaleMaxHeight, readerUpscaleModelName, readerPagesToPreload, readerPagedPageLayout, readerPagedPageOffset, readerPagedPageOffsetOverrides, readerSplitWideImages, readerReverseSplitOrder, readerVerticalInfiniteScroll, readerPillarbox, readerPillarboxAmount, readerPillarboxOrientation, readerOrientationLockEnabled, readerOrientationLockMask, readerReadThresholdPercent
        case readerFontSize, readerFontFamily, readerFontWeight, readerColorPreset, readerTextAlignment, readerLineSpacing, readerMargin
        case autoClearCacheEnabled, autoClearCacheThresholdMB, highQualityThreshold, backgroundHLSPipelineEnabled, readerDownloadsBackgroundEnabled, readerDownloadsWifiOnly, readerDownloadsParallelLimit, autoUpdateServicesEnabled, servicesAutoModeEnabled, servicesAutoSelectEpisodesEnabled, servicesAutoModeErrorIntelligenceEnabled, servicesAutoModeSourceIds, servicesAutoModeSourceOrderIds, servicesAutoModeQualityPreference, servicesResultMinimumSimilarity, servicesDropMismatchedResults, servicesStremioStyleSheetEnabled, servicesIncludedStreamLanguages, servicesHiddenStreamLanguages, servicesHideStreamsWithoutLanguageData, servicesAssumeOriginalAudio, servicesTreatDubbedAnimeAsEnglish, servicesHiddenStreamQualities, servicesHideStreamsWithoutDetectedQuality, servicesExtraRulesSourceIds, githubReleaseAutoCheckEnabled, githubReleaseUpdateAvailable, githubReleaseLatestVersion, githubReleaseURL, githubReleaseShowAlertPending, githubReleaseLastPromptedVersion, filterHorrorContent = "filterHorror", selectedSimilarityAlgorithm, performanceModeEnabled, performanceModeSkipAniListTraversalForAnimeDetails, performanceModeFastAnimeCatalogOverrides
        case kanzenHomeSelectedSourceID, kanzenRecentSourceSearches
        case collections, progressData, trackerState, catalogs, services, stremioAddons, skyStream, nuvioPlugins
        case mangaCollections, mangaReadingProgress, mangaCatalogs, customCatalogs, kanzenModules
        case readerExtensionsState, aidokuState
        case searchHistory, recommendationCache
        case userRatings, userRatingNotes
        case mediaStateSettings

        case profiles, activeProfileID
        case topLevelSettingKeys
        case servicesSettings, servicesSettingsWereCaptured
        case sharesServices
        case skyStreamSharedPayloads, nuvioSharedPayloads
    }

    private static let nonSettingCodingKeyRawValues: Set<String> = [
        "version", "createdDate",
        "collections", "progressData", "trackerState", "catalogs", "services",
        "stremioAddons", "skyStream", "nuvioPlugins",
        "mangaCollections", "mangaReadingProgress", "mangaCatalogs",
        "customCatalogs", "kanzenModules", "readerExtensionsState", "aidokuState",
        "searchHistory", "recommendationCache", "userRatings", "userRatingNotes",
        "mediaStateSettings", "profiles", "activeProfileID", "topLevelSettingKeys", "servicesSettings",
        "servicesSettingsWereCaptured",
        "sharesServices", "skyStreamSharedPayloads", "nuvioSharedPayloads"
    ]

    private static func decodedSettingKeyRawValues(
        in container: KeyedDecodingContainer<CodingKeys>
    ) -> Set<String> {
        Set(container.allKeys.compactMap { key in
            guard !nonSettingCodingKeyRawValues.contains(key.rawValue),
                  (try? container.decodeNil(forKey: key)) == false else {
                return nil
            }
            return key.rawValue
        })
    }

    private struct LossyRecommendationResults: Decodable {
        let values: [TMDBSearchResult]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let maximumCount = 10_000
            if let count = container.count, count > maximumCount {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Recommendation cache contains too many items."
                )
            }
            var decoded: [TMDBSearchResult] = []
            decoded.reserveCapacity(min(container.count ?? 0, maximumCount))
            var consumedCount = 0
            while !container.isAtEnd {
                guard consumedCount < maximumCount else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Recommendation cache contains too many items."
                    )
                }
                let candidate = try container.decode(LossyRecommendationResult.self)
                consumedCount += 1
                if let value = candidate.value {
                    decoded.append(value)
                }
            }
            values = decoded
        }
    }

    private struct LossyRecommendationResult: Decodable {
        let value: TMDBSearchResult?

        init(from decoder: Decoder) throws {
            value = try? TMDBSearchResult(from: decoder)
        }
    }

    fileprivate static func sanitizedDeclaredTopLevelSettingKeys(
        _ values: [String]?
    ) -> Set<String> {
        guard let values else { return [] }
        return Set(values.prefix(512).compactMap { rawKey in
            guard let key = CodingKeys(rawValue: rawKey),
                  !nonSettingCodingKeyRawValues.contains(key.rawValue) else {
                return nil
            }
            return key.rawValue
        })
    }

    static func decodedTopLevelSettingKeys(fromJSONObject json: [String: Any]) -> Set<String> {
        let candidates = Set(json.compactMap { rawKey, value -> String? in
            guard !(value is NSNull),
                  let key = CodingKeys(rawValue: rawKey),
                  !nonSettingCodingKeyRawValues.contains(key.rawValue) else {
                return nil
            }
            return key.rawValue
        })
        guard !candidates.isEmpty else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func strictlyDecodes(_ keys: Set<String>) -> Bool {
            var probe: [String: Any] = [
                "version": currentCloudSchemaVersion,
                "createdDate": "1970-01-01T00:00:00Z"
            ]
            for key in keys {
                probe[key] = json[key]
            }
            guard JSONSerialization.isValidJSONObject(probe),
                  let data = try? JSONSerialization.data(withJSONObject: probe) else {
                return false
            }
            return (try? decoder.decode(BackupData.self, from: data)) != nil
        }

        // The common lenient path is a malformed independent domain, not a
        // malformed setting. Validate the whole setting aggregate once, then
        // fall back to isolated probes only when one member is bad.
        if strictlyDecodes(candidates) { return candidates }
        return Set(candidates.filter { strictlyDecodes([$0]) })
    }

    static func topLevelSettingIsAuthoritative(
        storageKey: String,
        decodedWireKeys: Set<String>,
        allSettingsWereCaptured: Bool = false
    ) -> Bool {
        if allSettingsWereCaptured { return true }
        return settingWireKeys(forStorageKey: storageKey).contains {
            decodedWireKeys.contains($0)
        }
    }

    private static func settingWireKeys(forStorageKey storageKey: String) -> [String] {
        if storageKey.hasPrefix("kanzenReaderMode.") {
            return ["kanzenReaderModeOverrides"]
        }
        if storageKey.hasPrefix("Reader.pagedPageOffset.") {
            return ["readerPagedPageOffsetOverrides"]
        }
        if storageKey.hasPrefix("Reader.") {
            let suffix = storageKey.dropFirst("Reader.".count)
            guard let first = suffix.first else { return [] }
            return ["reader" + String(first).uppercased() + String(suffix.dropFirst())]
        }
        switch storageKey {
        case "eclipseThemeGradientColor":
            return ["settingsGradientColor"]
        case "readerThemeGradientColor":
            return ["readerSettingsGradientColor"]
        case "readerSelectedAppearance":
            return ["readerSelectedAppearance", "selectedAppearance"]
        case "readerAtmosphereStyle":
            return ["readerAtmosphereStyle", "atmosphereStyle"]
        case "readerAtmosphereSolidColorSource":
            return ["readerAtmosphereSolidColorSource", "atmosphereSolidColorSource"]
        case "kanzenReaderMode":
            return ["kanzenReaderMode", "readingMode"]
        case "playbackEngine", "inAppPlayer":
            return ["inAppPlayer", "playerChoice"]
        case "playerSubtitleAppearanceEnabled":
            return ["playerSubtitleAppearanceEnabled", "enableVLCSubtitleEditMenu"]
        case "showEpisodeBrowserButton":
            return ["showEpisodeBrowserButton", "showVLCEpisodeBrowserButton"]
        case "playerBrightnessGestureEnabled":
            return ["playerBrightnessGestureEnabled", "vlcBrightnessGestureEnabled"]
        case "playerVolumeGestureEnabled":
            return ["playerVolumeGestureEnabled", "vlcVolumeGestureEnabled"]
        case "playerDoubleTapSeekEnabled":
            return ["playerDoubleTapSeekEnabled", "vlcDoubleTapSeekEnabled"]
        case "playerDoubleTapSeekSeconds":
            return ["playerDoubleTapSeekSeconds", "vlcDoubleTapSeekSeconds"]
        case "playerOpenSubtitlesEnabled":
            return ["playerOpenSubtitlesEnabled", "vlcOpenSubtitlesEnabled"]
        case "playerOpenSubtitlesAutoFallbackEnabled":
            return ["playerOpenSubtitlesAutoFallbackEnabled", "vlcOpenSubtitlesAutoFallbackEnabled"]
        case "subtitles_foregroundColor":
            return ["subtitleForegroundColor"]
        case "subtitles_strokeColor":
            return ["subtitleStrokeColor"]
        case "subtitles_strokeWidth":
            return ["subtitleStrokeWidth"]
        case "subtitles_fontSize":
            return ["subtitleFontSize"]
        case "playerSubtitleOverlayBottomConstant":
            return ["subtitleVerticalOffset"]
        case "subtitles_isVisible":
            return ["subtitlesVisible"]
        case "showCastSection":
            return ["mediaDetailHiddenElements"]
        default:
            return [storageKey]
        }
    }

    func topLevelSettingIsAuthoritative(storageKey: String) -> Bool {
        Self.topLevelSettingIsAuthoritative(
            storageKey: storageKey,
            decodedWireKeys: decodedTopLevelSettingKeys,
            allSettingsWereCaptured: allTopLevelSettingsWereCaptured
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        accentColor = try Self.decodeColorData(from: container, forKey: .accentColor)
        settingsGradientColor = try Self.decodeColorData(from: container, forKey: .settingsGradientColor)
        readerAccentColor = try Self.decodeColorData(from: container, forKey: .readerAccentColor)
        tmdbLanguage = try container.decodeIfPresent(String.self, forKey: .tmdbLanguage) ?? "en-US"
        selectedAppearance = Self.sanitizedAppearance(try container.decodeIfPresent(String.self, forKey: .selectedAppearance))
        readerSelectedAppearance = Self.sanitizedAppearance(
            try container.decodeIfPresent(String.self, forKey: .readerSelectedAppearance)
                ?? selectedAppearance
        )
        readerGlobalAppearanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .readerGlobalAppearanceEnabled) ?? true
        readerSettingsGradientColor = try Self.decodeColorData(from: container, forKey: .readerSettingsGradientColor)
        enableSubtitlesByDefault = try container.decodeIfPresent(Bool.self, forKey: .enableSubtitlesByDefault) ?? false
        defaultSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .defaultSubtitleLanguage) ?? "eng"
        playerSubtitleAppearanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerSubtitleAppearanceEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .enableVLCSubtitleEditMenu)
            ?? true

        preferredAutoAudioLanguage = try container.decodeIfPresent(String.self, forKey: .preferredAutoAudioLanguage) ?? "eng"
        preferredAnimeAudioLanguage = try container.decodeIfPresent(String.self, forKey: .preferredAnimeAudioLanguage) ?? "jpn"

        inAppPlayer = Settings.normalizedInAppPlayer(
            try container.decodeIfPresent(String.self, forKey: .inAppPlayer)
                ?? container.decodeIfPresent(String.self, forKey: .playerChoice)
        )
        showScheduleTab = try container.decodeIfPresent(Bool.self, forKey: .showScheduleTab) ?? true
        showLocalScheduleTime = try container.decodeIfPresent(Bool.self, forKey: .showLocalScheduleTime) ?? true
        defaultScheduleMode = ScheduleMode.sanitizedRawValue(try container.decodeIfPresent(String.self, forKey: .defaultScheduleMode))
        scheduleWindowDays = ScheduleWindow.sanitizedDays(try container.decodeIfPresent(Int.self, forKey: .scheduleWindowDays))
        localNotificationSubscriptions = Self.sanitizedLocalNotificationSubscriptions(
            try container.decodeIfPresent(String.self, forKey: .localNotificationSubscriptions)
        )
        localNotificationEpisodeReminders = Self.sanitizedLocalNotificationEpisodeReminders(
            try container.decodeIfPresent(String.self, forKey: .localNotificationEpisodeReminders)
        )
        localNotificationEpisodeLeadTime = Self.sanitizedLocalNotificationEpisodeLeadTime(
            try container.decodeIfPresent(Int.self, forKey: .localNotificationEpisodeLeadTime)
        )
        localNotificationSeasonLeadTime = Self.sanitizedLocalNotificationSeasonLeadTime(
            try container.decodeIfPresent(Int.self, forKey: .localNotificationSeasonLeadTime)
        )
        localNotificationIncludeAnimeSpecials = try container.decodeIfPresent(Bool.self, forKey: .localNotificationIncludeAnimeSpecials)

        defaultPlaybackSpeed = Self.sanitizedDefaultPlaybackSpeed(
            try container.decodeIfPresent(Double.self, forKey: .defaultPlaybackSpeed)
        )
        holdSpeedPlayer = Self.sanitizedHoldSpeedPlayer(
            try container.decodeIfPresent(Double.self, forKey: .holdSpeedPlayer)
        )
        externalPlayer = try container.decodeIfPresent(String.self, forKey: .externalPlayer) ?? "none"
        preferDownloadedMedia = try container.decodeIfPresent(Bool.self, forKey: .preferDownloadedMedia) ?? false
        alwaysLandscape = try container.decodeIfPresent(Bool.self, forKey: .alwaysLandscape) ?? false
        playerPlaybackLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerPlaybackLockEnabled) ?? PlayerPlaybackLockSettings.defaultEnabled
        aniSkipEnabled = try container.decodeIfPresent(Bool.self, forKey: .aniSkipEnabled) ?? true
        introDBEnabled = try container.decodeIfPresent(Bool.self, forKey: .introDBEnabled) ?? true
        introDBAppEnabled = try container.decodeIfPresent(Bool.self, forKey: .introDBAppEnabled) ?? true
        aniSkipAutoSkip = try container.decodeIfPresent(Bool.self, forKey: .aniSkipAutoSkip) ?? false
        skip85sEnabled = try container.decodeIfPresent(Bool.self, forKey: .skip85sEnabled) ?? false
        skip85sAlwaysVisible = try container.decodeIfPresent(Bool.self, forKey: .skip85sAlwaysVisible) ?? false
        showNextEpisodeButton = try container.decodeIfPresent(Bool.self, forKey: .showNextEpisodeButton) ?? true
        showEpisodeBrowserButton = try container.decodeIfPresent(Bool.self, forKey: .showEpisodeBrowserButton)
            ?? container.decodeIfPresent(Bool.self, forKey: .showVLCEpisodeBrowserButton)
            ?? true
        showPlayerServicesButton = try container.decodeIfPresent(Bool.self, forKey: .showPlayerServicesButton) ?? false
        showNextEpisodePosterButton = try container.decodeIfPresent(Bool.self, forKey: .showNextEpisodePosterButton) ?? false
        nextEpisodeThreshold = Self.sanitizedNextEpisodeThreshold(
            try container.decodeIfPresent(Double.self, forKey: .nextEpisodeThreshold)
        )
        nextEpisodeSkipFillerEnabled = try container.decodeIfPresent(Bool.self, forKey: .nextEpisodeSkipFillerEnabled) ?? NextEpisodeFillerSettings.defaultEnabled
        playerBrightnessGestureEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerBrightnessGestureEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .vlcBrightnessGestureEnabled)
            ?? false
        playerVolumeGestureEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerVolumeGestureEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .vlcVolumeGestureEnabled)
            ?? false
        playerTwoFingerTapPlayPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerTwoFingerTapPlayPauseEnabled) ?? true
        playerCenterTapPlayPauseEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerCenterTapPlayPauseEnabled) ?? true
        playerDoubleTapSeekEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerDoubleTapSeekEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .vlcDoubleTapSeekEnabled)
            ?? true
        playerDoubleTapSeekSeconds = Self.sanitizedPlayerDoubleTapSeekSeconds(
            try container.decodeIfPresent(Double.self, forKey: .playerDoubleTapSeekSeconds)
                ?? container.decodeIfPresent(Double.self, forKey: .vlcDoubleTapSeekSeconds)
        )
        playerOpenSubtitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerOpenSubtitlesEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .vlcOpenSubtitlesEnabled)
            ?? false
        playerOpenSubtitlesAutoFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerOpenSubtitlesAutoFallbackEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .vlcOpenSubtitlesAutoFallbackEnabled)
            ?? true
        playerPerformanceOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerPerformanceOverlayEnabled) ?? false
        mpvForegroundFPS = Self.sanitizedMPVForegroundFPS(try container.decodeIfPresent(Int.self, forKey: .mpvForegroundFPS) ?? 30)
        mpvRenderBackend = Self.sanitizedMPVRenderBackend(try container.decodeIfPresent(String.self, forKey: .mpvRenderBackend))
        mpvMetalQualityProfile = Self.sanitizedMPVMetalQualityProfile(try container.decodeIfPresent(String.self, forKey: .mpvMetalQualityProfile))
        mpvUpscalingMode = Self.sanitizedMPVUpscalingMode(try container.decodeIfPresent(String.self, forKey: .mpvUpscalingMode))
        mpvNeuralUpscaler = Self.sanitizedMPVNeuralUpscaler(try container.decodeIfPresent(String.self, forKey: .mpvNeuralUpscaler))
        mpvNeuralUpscalerTV = Self.sanitizedMPVNeuralUpscaler(try container.decodeIfPresent(String.self, forKey: .mpvNeuralUpscalerTV))
        mpvPlayerSkin = Self.sanitizedMPVPlayerSkin(try container.decodeIfPresent(String.self, forKey: .mpvPlayerSkin))
        mpvPlayerSkinCustomPrimaryColor = try Self.decodeColorData(from: container, forKey: .mpvPlayerSkinCustomPrimaryColor)
        mpvPlayerSkinCustomSecondaryColor = try Self.decodeColorData(from: container, forKey: .mpvPlayerSkinCustomSecondaryColor)
        mpvPlayerSkinAnimationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .mpvPlayerSkinAnimationsEnabled) ?? MPVPlayerSkinSettings.defaultAnimationsEnabled
        mpvPlayerSkinTintControlsOnly = try container.decodeIfPresent(Bool.self, forKey: .mpvPlayerSkinTintControlsOnly) ?? MPVPlayerSkinSettings.defaultTintControlsOnly
        mpvPictureInPictureEnabled = try container.decodeIfPresent(Bool.self, forKey: .mpvPictureInPictureEnabled) ?? true
        mpvAppExitPictureInPictureEnabled = try container.decodeIfPresent(Bool.self, forKey: .mpvAppExitPictureInPictureEnabled) ?? false
        mpvHDRMode = MPVHDRMode(rawValue: try container.decodeIfPresent(String.self, forKey: .mpvHDRMode) ?? MPVHDRMode.defaultMode.rawValue)?.rawValue ?? MPVHDRMode.defaultMode.rawValue
        mpvSurroundSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .mpvSurroundSoundEnabled) ?? true
        watchTogetherEnabled = try container.decodeIfPresent(Bool.self, forKey: .watchTogetherEnabled) ?? WatchTogetherSettings.defaultEnabled
        smartInAppPlayerChoosingEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartInAppPlayerChoosingEnabled) ?? false
        experimentalFeaturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalFeaturesEnabled)
        experimentalFeaturesLastChangedAt = Self.sanitizedExperimentalFeaturesLastChangedAt(
            try container.decodeIfPresent(Double.self, forKey: .experimentalFeaturesLastChangedAt)
        )
        experimentalMPVPreloadEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVPreloadEnabled) ?? true
        experimentalMPVSmoothTransitionEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVSmoothTransitionEnabled) ?? true
        experimentalMPVPreloadCellularEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVPreloadCellularEnabled) ?? false
        experimentalMPVPreloadWifiLimitMB = ExperimentalFeatureState.resolvedMPVPreloadWifiLimitMB(try container.decodeIfPresent(Int.self, forKey: .experimentalMPVPreloadWifiLimitMB) ?? ExperimentalFeatureState.mpvPreloadWifiDefaultLimitMB)
        experimentalMPVPreloadCellularLimitMB = ExperimentalFeatureState.resolvedMPVPreloadCellularLimitMB(try container.decodeIfPresent(Int.self, forKey: .experimentalMPVPreloadCellularLimitMB) ?? ExperimentalFeatureState.mpvPreloadCellularDefaultLimitMB)
        experimentalMPVShowRemainingTime = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVShowRemainingTime) ?? true
        experimentalMPVPreciseProgress = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVPreciseProgress) ?? true
        experimentalMPVIgnoreSpecialSubtitleStyles = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVIgnoreSpecialSubtitleStyles) ?? false
        experimentalMPVPreloadAutoClear = try container.decodeIfPresent(Bool.self, forKey: .experimentalMPVPreloadAutoClear) ?? true
        experimentalICloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalICloudSyncEnabled) ?? false

        subtitleForegroundColor = try Self.decodeColorData(from: container, forKey: .subtitleForegroundColor)
        subtitleStrokeColor = try Self.decodeColorData(from: container, forKey: .subtitleStrokeColor)
        subtitleStrokeWidth = Self.sanitizedSubtitleStrokeWidth(
            try container.decodeIfPresent(Double.self, forKey: .subtitleStrokeWidth)
        )
        subtitleFontSize = Self.sanitizedSubtitleFontSize(
            try container.decodeIfPresent(Double.self, forKey: .subtitleFontSize)
        )
        subtitleVerticalOffset = Self.sanitizedSubtitleVerticalOffset(
            try container.decodeIfPresent(Double.self, forKey: .subtitleVerticalOffset)
        )
        subtitlesVisible = try container.decodeIfPresent(Bool.self, forKey: .subtitlesVisible) ?? false

        showKanzen = try container.decodeIfPresent(Bool.self, forKey: .showKanzen) ?? false
        hideSplashScreen = try container.decodeIfPresent(Bool.self, forKey: .hideSplashScreen)
        modeSwitchAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .modeSwitchAnimationEnabled) ?? ModeSwitchAnimationSettings.defaultEnabled
        kanzenAutoUpdateModules = try container.decodeIfPresent(Bool.self, forKey: .kanzenAutoUpdateModules) ?? true
        seasonMenu = try container.decodeIfPresent(Bool.self, forKey: .seasonMenu) ?? false
        horizontalEpisodeList = try container.decodeIfPresent(Bool.self, forKey: .horizontalEpisodeList) ?? false
        mediaDetailTitleArtworkEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaDetailTitleArtworkEnabled) ?? MediaDetailTitleArtworkSettings.defaultEnabled
        mediaDetailAlternatePosterEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaDetailAlternatePosterEnabled) ?? MediaDetailAlternatePosterSettings.defaultEnabled
        mediaDetailSimilarTitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaDetailSimilarTitlesEnabled) ?? MediaDetailSimilarTitlesSettings.defaultEnabled
        useClassicScheduleUI = try container.decodeIfPresent(Bool.self, forKey: .useClassicScheduleUI) ?? false
        heroBannerCatalogId = Self.sanitizedNonEmptyString(try container.decodeIfPresent(String.self, forKey: .heroBannerCatalogId), defaultValue: "trending")
        homeCatalogLayoutOverrides = try container.decodeIfPresent(String.self, forKey: .homeCatalogLayoutOverrides) ?? ""
        homeAnimatedBackgroundEnabled = try container.decodeIfPresent(Bool.self, forKey: .homeAnimatedBackgroundEnabled)
        homeAnimatedBackgroundQuality = Self.sanitizedHomeAnimatedBackgroundQuality(try container.decodeIfPresent(String.self, forKey: .homeAnimatedBackgroundQuality))
        homeAnimatedBackgroundFrameRate = Self.sanitizedHomeAnimatedBackgroundFrameRate(try container.decodeIfPresent(String.self, forKey: .homeAnimatedBackgroundFrameRate))
        appPerformanceOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .appPerformanceOverlayEnabled) ?? AppPerformanceOverlaySettings.defaultEnabled
        heroBannerBehavior = Self.sanitizedHeroBannerBehavior(try container.decodeIfPresent(String.self, forKey: .heroBannerBehavior))
        experimentalMediaDesignPreset = Self.sanitizedExperimentalMediaDesignPreset(try container.decodeIfPresent(String.self, forKey: .experimentalMediaDesignPreset))
        experimentalHeroBleedLevel = Self.sanitizedExperimentalHeroBleedLevel(try container.decodeIfPresent(String.self, forKey: .experimentalHeroBleedLevel))
        experimentalHomeCardShape = Self.sanitizedExperimentalHomeCardShape(try container.decodeIfPresent(String.self, forKey: .experimentalHomeCardShape))
        experimentalMultiGradientPalette = Self.sanitizedExperimentalMultiGradientPalette(try container.decodeIfPresent(String.self, forKey: .experimentalMultiGradientPalette))
        experimentalHeroHeightScale = Self.sanitizedExperimentalHeroHeightScale(try container.decodeIfPresent(Double.self, forKey: .experimentalHeroHeightScale))
        experimentalHeroBleedStrength = Self.sanitizedExperimentalHeroBleedStrength(try container.decodeIfPresent(Double.self, forKey: .experimentalHeroBleedStrength))
        experimentalHeroFadeDistanceScale = Self.sanitizedExperimentalHeroFadeDistanceScale(try container.decodeIfPresent(Double.self, forKey: .experimentalHeroFadeDistanceScale))
        experimentalSectionSpacingScale = Self.sanitizedExperimentalSectionSpacingScale(try container.decodeIfPresent(Double.self, forKey: .experimentalSectionSpacingScale))
        experimentalCardRadiusScale = Self.sanitizedExperimentalCardRadiusScale(try container.decodeIfPresent(Double.self, forKey: .experimentalCardRadiusScale))
        experimentalMediaCardScale = Self.sanitizedExperimentalMediaCardScale(try container.decodeIfPresent(Double.self, forKey: .experimentalMediaCardScale))
        experimentalGlassStrength = Self.sanitizedExperimentalGlassStrength(try container.decodeIfPresent(Double.self, forKey: .experimentalGlassStrength))
        experimentalGradientBaseDarkness = Self.sanitizedExperimentalGradientBaseDarkness(try container.decodeIfPresent(Double.self, forKey: .experimentalGradientBaseDarkness))
        experimentalGradientAccentIntensity = Self.sanitizedExperimentalGradientAccentIntensity(try container.decodeIfPresent(Double.self, forKey: .experimentalGradientAccentIntensity))
        experimentalGradientScrollMotion = Self.sanitizedExperimentalGradientScrollMotion(try container.decodeIfPresent(Double.self, forKey: .experimentalGradientScrollMotion))
        experimentalGradientUseCustomColors = try container.decodeIfPresent(Bool.self, forKey: .experimentalGradientUseCustomColors) ?? false
        experimentalGradientColorA = try Self.decodeColorData(from: container, forKey: .experimentalGradientColorA)
        experimentalGradientColorB = try Self.decodeColorData(from: container, forKey: .experimentalGradientColorB)
        experimentalGradientColorC = try Self.decodeColorData(from: container, forKey: .experimentalGradientColorC)
        atmosphereStyle = Self.sanitizedAtmosphereStyle(try container.decodeIfPresent(String.self, forKey: .atmosphereStyle))
        atmosphereSolidColorSource = Self.sanitizedAtmosphereSolidColorSource(try container.decodeIfPresent(String.self, forKey: .atmosphereSolidColorSource))
        atmosphereSolidColor = try Self.decodeColorData(from: container, forKey: .atmosphereSolidColor)
        readerAtmosphereStyle = Self.sanitizedAtmosphereStyle(
            try container.decodeIfPresent(String.self, forKey: .readerAtmosphereStyle)
                ?? atmosphereStyle
        )
        readerAtmosphereSolidColorSource = Self.sanitizedAtmosphereSolidColorSource(
            try container.decodeIfPresent(String.self, forKey: .readerAtmosphereSolidColorSource)
                ?? atmosphereSolidColorSource
        )
        readerAtmosphereSolidColor = try Self.decodeColorData(from: container, forKey: .readerAtmosphereSolidColor)
        mediaDetailElementOrder = Self.sanitizedMediaDetailElementOrder(try container.decodeIfPresent(String.self, forKey: .mediaDetailElementOrder))
        mediaDetailHiddenElements = Self.sanitizedMediaDetailHiddenElements(try container.decodeIfPresent(String.self, forKey: .mediaDetailHiddenElements))
        readerDetailElementOrder = Self.sanitizedReaderDetailElementOrder(try container.decodeIfPresent(String.self, forKey: .readerDetailElementOrder))
        readerDetailHiddenElements = Self.sanitizedReaderDetailHiddenElements(try container.decodeIfPresent(String.self, forKey: .readerDetailHiddenElements))
        mediaColumnsPortrait = try container.decodeIfPresent(Int.self, forKey: .mediaColumnsPortrait) ?? 3
        mediaColumnsLandscape = try container.decodeIfPresent(Int.self, forKey: .mediaColumnsLandscape) ?? 5

        readingMode = try container.decodeIfPresent(Int.self, forKey: .readingMode) ?? 2
        if let decodedKanzenReaderMode = try container.decodeIfPresent(String.self, forKey: .kanzenReaderMode) {
            kanzenReaderMode = Self.sanitizedKanzenReaderMode(decodedKanzenReaderMode)
        } else {
            kanzenReaderMode = Self.kanzenReaderModeRawValue(forReadingMode: readingMode)
        }
        kanzenReaderModeOverrides = Self.sanitizedKanzenReaderModeOverrides(try container.decodeIfPresent([String: String].self, forKey: .kanzenReaderModeOverrides))
        readerDownsampleImages = try container.decodeIfPresent(Bool.self, forKey: .readerDownsampleImages) ?? true
        readerCropBorders = try container.decodeIfPresent(Bool.self, forKey: .readerCropBorders) ?? false
        readerDisableQuickActions = try container.decodeIfPresent(Bool.self, forKey: .readerDisableQuickActions) ?? false
        readerDisableDoubleTap = try container.decodeIfPresent(Bool.self, forKey: .readerDisableDoubleTap) ?? false
        readerLiveText = try container.decodeIfPresent(Bool.self, forKey: .readerLiveText) ?? false
        readerHideBarsOnSwipe = try container.decodeIfPresent(Bool.self, forKey: .readerHideBarsOnSwipe) ?? false
        readerBackgroundColor = Self.sanitizedReaderBackgroundColor(try container.decodeIfPresent(String.self, forKey: .readerBackgroundColor))
        readerOrientation = Self.sanitizedReaderOrientation(try container.decodeIfPresent(String.self, forKey: .readerOrientation))
        readerTapZones = Self.sanitizedReaderTapZones(try container.decodeIfPresent(String.self, forKey: .readerTapZones))
        readerInvertTapZones = try container.decodeIfPresent(Bool.self, forKey: .readerInvertTapZones) ?? false
        readerAnimatePageTransitions = try container.decodeIfPresent(Bool.self, forKey: .readerAnimatePageTransitions) ?? true
        readerUpscaleImages = try container.decodeIfPresent(Bool.self, forKey: .readerUpscaleImages) ?? false
        readerUpscaleMaxHeight = Self.sanitizedReaderUpscaleMaxHeight(try container.decodeIfPresent(Int.self, forKey: .readerUpscaleMaxHeight))
        readerUpscaleModelName = try container.decodeIfPresent(String.self, forKey: .readerUpscaleModelName) ?? "None"
        readerPagesToPreload = Self.sanitizedReaderPagesToPreload(try container.decodeIfPresent(Int.self, forKey: .readerPagesToPreload))
        readerPagedPageLayout = Self.sanitizedReaderPagedPageLayout(try container.decodeIfPresent(String.self, forKey: .readerPagedPageLayout))
        readerPagedPageOffset = try container.decodeIfPresent(Bool.self, forKey: .readerPagedPageOffset) ?? false
        readerPagedPageOffsetOverrides = Self.sanitizedReaderPagedPageOffsetOverrides(try container.decodeIfPresent([String: Bool].self, forKey: .readerPagedPageOffsetOverrides))
        readerSplitWideImages = try container.decodeIfPresent(Bool.self, forKey: .readerSplitWideImages) ?? false
        readerReverseSplitOrder = try container.decodeIfPresent(Bool.self, forKey: .readerReverseSplitOrder) ?? false
        readerVerticalInfiniteScroll = try container.decodeIfPresent(Bool.self, forKey: .readerVerticalInfiniteScroll) ?? true
        readerPillarbox = try container.decodeIfPresent(Bool.self, forKey: .readerPillarbox) ?? false
        readerPillarboxAmount = Self.sanitizedReaderPillarboxAmount(try container.decodeIfPresent(Double.self, forKey: .readerPillarboxAmount))
        readerPillarboxOrientation = Self.sanitizedReaderPillarboxOrientation(try container.decodeIfPresent(String.self, forKey: .readerPillarboxOrientation))
        readerOrientationLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .readerOrientationLockEnabled) ?? false
        readerOrientationLockMask = Self.sanitizedReaderOrientationLockMask(try container.decodeIfPresent(String.self, forKey: .readerOrientationLockMask))
        readerReadThresholdPercent = Self.sanitizedReaderReadThresholdPercent(try container.decodeIfPresent(Double.self, forKey: .readerReadThresholdPercent))

        readerFontSize = Self.sanitizedReaderFontSize(
            try container.decodeIfPresent(Double.self, forKey: .readerFontSize)
        )
        readerFontFamily = try container.decodeIfPresent(String.self, forKey: .readerFontFamily) ?? "-apple-system"
        readerFontWeight = try container.decodeIfPresent(String.self, forKey: .readerFontWeight) ?? "normal"
        readerColorPreset = Self.sanitizedReaderColorPreset(try container.decodeIfPresent(Int.self, forKey: .readerColorPreset))
        readerTextAlignment = try container.decodeIfPresent(String.self, forKey: .readerTextAlignment) ?? "left"
        readerLineSpacing = Self.sanitizedReaderLineSpacing(
            try container.decodeIfPresent(Double.self, forKey: .readerLineSpacing)
        )
        readerMargin = Self.sanitizedReaderMargin(
            try container.decodeIfPresent(Double.self, forKey: .readerMargin)
        )

        autoClearCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoClearCacheEnabled) ?? false
        autoClearCacheThresholdMB = Self.sanitizedAutoClearCacheThresholdMB(
            try container.decodeIfPresent(Double.self, forKey: .autoClearCacheThresholdMB)
        )
        highQualityThreshold = Self.sanitizedHighQualityThreshold(
            try container.decodeIfPresent(Double.self, forKey: .highQualityThreshold)
        )
        backgroundHLSPipelineEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundHLSPipelineEnabled) ?? false
        readerDownloadsBackgroundEnabled = try container.decodeIfPresent(Bool.self, forKey: .readerDownloadsBackgroundEnabled) ?? true
        readerDownloadsWifiOnly = try container.decodeIfPresent(Bool.self, forKey: .readerDownloadsWifiOnly) ?? false
        readerDownloadsParallelLimit = Self.sanitizedReaderDownloadsParallelLimit(try container.decodeIfPresent(Int.self, forKey: .readerDownloadsParallelLimit))
        autoUpdateServicesEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateServicesEnabled) ?? true
        servicesAutoModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .servicesAutoModeEnabled) ?? AutoModeSettings.defaultEnabled
        servicesAutoSelectEpisodesEnabled = try container.decodeIfPresent(Bool.self, forKey: .servicesAutoSelectEpisodesEnabled) ?? false
        servicesAutoModeErrorIntelligenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .servicesAutoModeErrorIntelligenceEnabled) ?? AutoModeErrorIntelligenceSettings.defaultEnabled
        servicesAutoModeSourceIds = Self.sanitizedStringList(try container.decodeIfPresent([String].self, forKey: .servicesAutoModeSourceIds))
        servicesAutoModeSourceOrderIds = Self.sanitizedStringList(try container.decodeIfPresent([String].self, forKey: .servicesAutoModeSourceOrderIds))
        servicesAutoModeQualityPreference = AutoModeQualityPreference.sanitizedRawValue(try container.decodeIfPresent(String.self, forKey: .servicesAutoModeQualityPreference))
        servicesResultMinimumSimilarity = Self.sanitizedServicesResultMinimumSimilarity(try container.decodeIfPresent(Double.self, forKey: .servicesResultMinimumSimilarity))
        servicesDropMismatchedResults = try container.decodeIfPresent(Bool.self, forKey: .servicesDropMismatchedResults) ?? ServicesResultRankingSettings.defaultDropMismatchedResults
        servicesStremioStyleSheetEnabled = try container.decodeIfPresent(Bool.self, forKey: .servicesStremioStyleSheetEnabled) ?? ServicesSheetPresentationSettings.defaultStremioStyleEnabled
        servicesIncludedStreamLanguages = StreamLanguageFilter.sanitizedLanguageList(try container.decodeIfPresent([String].self, forKey: .servicesIncludedStreamLanguages) ?? [])
        servicesHiddenStreamLanguages = StreamLanguageFilter.sanitizedLanguageList(try container.decodeIfPresent([String].self, forKey: .servicesHiddenStreamLanguages) ?? [])
        servicesHideStreamsWithoutLanguageData = try container.decodeIfPresent(Bool.self, forKey: .servicesHideStreamsWithoutLanguageData) ?? false
        servicesAssumeOriginalAudio = try container.decodeIfPresent(Bool.self, forKey: .servicesAssumeOriginalAudio) ?? false
        servicesTreatDubbedAnimeAsEnglish = try container.decodeIfPresent(Bool.self, forKey: .servicesTreatDubbedAnimeAsEnglish) ?? false
        servicesHiddenStreamQualities = StreamLanguageFilter.sanitizedQualityHeights(try container.decodeIfPresent([Int].self, forKey: .servicesHiddenStreamQualities) ?? [])
        servicesHideStreamsWithoutDetectedQuality = try container.decodeIfPresent(Bool.self, forKey: .servicesHideStreamsWithoutDetectedQuality) ?? false
        if let decodedSourceIds = try container.decodeIfPresent([String].self, forKey: .servicesExtraRulesSourceIds) {
            servicesExtraRulesSourceIds = StreamLanguageFilter.sanitizedExtraRulesSourceIds(decodedSourceIds)
        } else {
            servicesExtraRulesSourceIds = nil
        }
        githubReleaseAutoCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .githubReleaseAutoCheckEnabled) ?? true
        githubReleaseUpdateAvailable = try container.decodeIfPresent(Bool.self, forKey: .githubReleaseUpdateAvailable) ?? false
        githubReleaseLatestVersion = try container.decodeIfPresent(String.self, forKey: .githubReleaseLatestVersion) ?? ""
        githubReleaseURL = try container.decodeIfPresent(String.self, forKey: .githubReleaseURL) ?? ""
        githubReleaseShowAlertPending = try container.decodeIfPresent(Bool.self, forKey: .githubReleaseShowAlertPending) ?? false
        githubReleaseLastPromptedVersion = try container.decodeIfPresent(String.self, forKey: .githubReleaseLastPromptedVersion) ?? ""
        filterHorrorContent = try container.decodeIfPresent(Bool.self, forKey: .filterHorrorContent) ?? false
        selectedSimilarityAlgorithm = Self.sanitizedSimilarityAlgorithm(try container.decodeIfPresent(String.self, forKey: .selectedSimilarityAlgorithm))
        performanceModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .performanceModeEnabled) ?? PerformanceModeSettings.defaultEnabled
        performanceModeSkipAniListTraversalForAnimeDetails = try container.decodeIfPresent(Bool.self, forKey: .performanceModeSkipAniListTraversalForAnimeDetails) ?? false
        let decodedPerformanceOverrides = try container.decodeIfPresent([String: Bool].self, forKey: .performanceModeFastAnimeCatalogOverrides) ?? [:]
        performanceModeFastAnimeCatalogOverrides = decodedPerformanceOverrides.filter { PerformanceModeSettings.animeCatalogIds.contains($0.key) }
        kanzenHomeSelectedSourceID = try container.decodeIfPresent(String.self, forKey: .kanzenHomeSelectedSourceID) ?? ""
        kanzenRecentSourceSearches = try container.decodeIfPresent([String].self, forKey: .kanzenRecentSourceSearches) ?? []

        let decodedCollections = try container.decodeIfPresent(
            [BackupCollection].self,
            forKey: .collections
        )
        let decodedProgress = try container.decodeIfPresent(
            ProgressData.self,
            forKey: .progressData
        )
        let decodedTrackerState = try container.decodeIfPresent(
            TrackerState.self,
            forKey: .trackerState
        )
        let decodedCatalogs = try container.decodeIfPresent(
            [Catalog].self,
            forKey: .catalogs
        )
        let decodedServices = try container.decodeIfPresent(
            [BackupService].self,
            forKey: .services
        )
        collections = Self.sanitizedCollections(decodedCollections ?? [])
        progressData = Self.sanitizedProgressData(decodedProgress ?? ProgressData())
        trackerState = decodedTrackerState ?? TrackerState()
        catalogs = decodedCatalogs ?? []
        services = decodedServices ?? []
        stremioAddons = try container.decodeIfPresent([BackupStremioAddon].self, forKey: .stremioAddons)
        skyStream = try container.decodeIfPresent(SkyStreamBackupSnapshot.self, forKey: .skyStream)
        nuvioPlugins = try container.decodeIfPresent(NuvioStoredPluginsState.self, forKey: .nuvioPlugins)
        mangaCollections = try container.decodeIfPresent([BackupMangaCollection].self, forKey: .mangaCollections) ?? []
        mangaReadingProgress = try container.decodeIfPresent([String: MangaProgress].self, forKey: .mangaReadingProgress) ?? [:]
        mangaCatalogs = try container.decodeIfPresent([MangaCatalog].self, forKey: .mangaCatalogs) ?? []
        customCatalogs = try container.decodeIfPresent([KanzenCustomCatalog].self, forKey: .customCatalogs) ?? []
        kanzenModules = try container.decodeIfPresent([BackupKanzenModule].self, forKey: .kanzenModules) ?? []
        aidokuState = try container.decodeIfPresent(BackupAidokuState.self, forKey: .aidokuState)
            .map(Self.aidokuStateWithoutExecutablePayloads)
        readerExtensionsState = try container.decodeIfPresent(
            BackupReaderExtensionState.self,
            forKey: .readerExtensionsState
        ) ?? aidokuState.map(BackupReaderExtensionState.migratingLegacyAidoku)
        searchHistory = try container.decodeIfPresent(BackupSearchHistory.self, forKey: .searchHistory) ?? BackupSearchHistory()
        let decodedRecommendationCache = try? container.decodeIfPresent(
            LossyRecommendationResults.self,
            forKey: .recommendationCache
        )
        recommendationCache = Self.sanitizedRecommendationCache(
            decodedRecommendationCache?.values ?? []
        )
        let decodedUserRatings = Self.decodeUserRatingsIfPresent(from: container)
        let decodedUserRatingNotes = try container.decodeIfPresent(
            [String: String].self,
            forKey: .userRatingNotes
        )
        userRatings = decodedUserRatings ?? [:]
        userRatingNotes = Self.sanitizedUserRatingNotes(decodedUserRatingNotes ?? [:])
        mediaStateSettings = try container.decodeIfPresent([String: Data].self, forKey: .mediaStateSettings)

        let decodedServicesSettings = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .servicesSettings
        )
        servicesSettings = Self.servicesSettingsForExperimentalCloudSync(
            decodedServicesSettings
        )
        servicesSettingsWereCaptured = (
            try container.decodeIfPresent(Bool.self, forKey: .servicesSettingsWereCaptured)
                ?? false
        ) && servicesSettings != nil
        sharesServices = try container.decodeIfPresent(Bool.self, forKey: .sharesServices)
        profiles = try container.decodeIfPresent([BackupProfileSnapshot].self, forKey: .profiles)
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        skyStreamSharedPayloads = try container.decodeIfPresent(
            [BackupSkyStreamSharedPayload].self,
            forKey: .skyStreamSharedPayloads
        )
        nuvioSharedPayloads = try container.decodeIfPresent(
            [BackupNuvioSharedPayload].self,
            forKey: .nuvioSharedPayloads
        )
        hasCollections = decodedCollections != nil
        hasProgressData = decodedProgress != nil
        hasTrackerState = decodedTrackerState != nil
        hasCatalogs = decodedCatalogs != nil
        hasServices = decodedServices != nil
        hasMangaCollections = container.decodePresence(of: [BackupMangaCollection].self, forKey: .mangaCollections)
        hasMangaReadingProgress = container.decodePresence(of: [String: MangaProgress].self, forKey: .mangaReadingProgress)
        hasMangaCatalogs = container.decodePresence(of: [MangaCatalog].self, forKey: .mangaCatalogs)
        hasCustomCatalogs = container.decodePresence(of: [KanzenCustomCatalog].self, forKey: .customCatalogs)
        hasKanzenModules = container.decodePresence(of: [BackupKanzenModule].self, forKey: .kanzenModules)
        hasUserRatings = decodedUserRatings != nil && decodedUserRatingNotes != nil
        allTopLevelSettingsWereCaptured = false
        let decodedSettingKeys = Self.decodedSettingKeyRawValues(in: container)
        if container.contains(.topLevelSettingKeys) {
            let declaredKeys = try? container.decode(
                [String].self,
                forKey: .topLevelSettingKeys
            )
            decodedTopLevelSettingKeys = decodedSettingKeys.intersection(
                Self.sanitizedDeclaredTopLevelSettingKeys(declaredKeys)
            )
        } else {
            // Backward compatibility: legacy backups predate the authority
            // list, so each successfully decoded scalar key authorizes itself.
            decodedTopLevelSettingKeys = decodedSettingKeys
        }
        let decodedOptionalColorSettings: [(String, Data?)] = [
            (CodingKeys.accentColor.rawValue, accentColor),
            (CodingKeys.settingsGradientColor.rawValue, settingsGradientColor),
            (CodingKeys.readerAccentColor.rawValue, readerAccentColor),
            (CodingKeys.readerSettingsGradientColor.rawValue, readerSettingsGradientColor),
            (CodingKeys.mpvPlayerSkinCustomPrimaryColor.rawValue, mpvPlayerSkinCustomPrimaryColor),
            (CodingKeys.mpvPlayerSkinCustomSecondaryColor.rawValue, mpvPlayerSkinCustomSecondaryColor),
            (CodingKeys.subtitleForegroundColor.rawValue, subtitleForegroundColor),
            (CodingKeys.subtitleStrokeColor.rawValue, subtitleStrokeColor),
            (CodingKeys.experimentalGradientColorA.rawValue, experimentalGradientColorA),
            (CodingKeys.experimentalGradientColorB.rawValue, experimentalGradientColorB),
            (CodingKeys.experimentalGradientColorC.rawValue, experimentalGradientColorC),
            (CodingKeys.atmosphereSolidColor.rawValue, atmosphereSolidColor),
            (CodingKeys.readerAtmosphereSolidColor.rawValue, readerAtmosphereSolidColor)
        ]
        for (key, value) in decodedOptionalColorSettings where value == nil {
            decodedTopLevelSettingKeys.remove(key)
        }
    }

    static func decodeColorData(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data? {
        if let data = try? container.decodeIfPresent(Data.self, forKey: key) {
            return data
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return backupColorData(from: string)
        }
        return nil
    }

    static func backupColorData(from value: Any?) -> Data? {
        if let data = value as? Data {
            return data
        }
        guard let string = value as? String else {
            return nil
        }
        if let colorData = archivedColorData(fromHexString: string) {
            return colorData
        }
        return Data(base64Encoded: string)
    }

    private static func archivedColorData(fromHexString rawValue: String) -> Data? {
        let raw = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard raw.count == 6 || raw.count == 8, raw.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        let scanner = Scanner(string: raw)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            return nil
        }
        let alpha: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        if raw.count == 8 {
            alpha = CGFloat((value >> 24) & 0xFF) / 255.0
            red = CGFloat((value >> 16) & 0xFF) / 255.0
            green = CGFloat((value >> 8) & 0xFF) / 255.0
            blue = CGFloat(value & 0xFF) / 255.0
        } else {
            alpha = 1.0
            red = CGFloat((value >> 16) & 0xFF) / 255.0
            green = CGFloat((value >> 8) & 0xFF) / 255.0
            blue = CGFloat(value & 0xFF) / 255.0
        }
        let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
        return try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(createdDate, forKey: .createdDate)
        if !allTopLevelSettingsWereCaptured {
            try container.encode(
                decodedTopLevelSettingKeys.sorted(),
                forKey: .topLevelSettingKeys
            )
        }
        try container.encodeIfPresent(accentColor, forKey: .accentColor)
        try container.encodeIfPresent(settingsGradientColor, forKey: .settingsGradientColor)
        try container.encodeIfPresent(readerAccentColor, forKey: .readerAccentColor)
        try container.encode(tmdbLanguage, forKey: .tmdbLanguage)
        try container.encode(Self.sanitizedAppearance(selectedAppearance), forKey: .selectedAppearance)
        try container.encode(Self.sanitizedAppearance(readerSelectedAppearance), forKey: .readerSelectedAppearance)
        try container.encode(readerGlobalAppearanceEnabled, forKey: .readerGlobalAppearanceEnabled)
        try container.encodeIfPresent(readerSettingsGradientColor, forKey: .readerSettingsGradientColor)
        try container.encode(enableSubtitlesByDefault, forKey: .enableSubtitlesByDefault)
        try container.encode(defaultSubtitleLanguage, forKey: .defaultSubtitleLanguage)
        try container.encode(playerSubtitleAppearanceEnabled, forKey: .playerSubtitleAppearanceEnabled)

        try container.encode(preferredAutoAudioLanguage, forKey: .preferredAutoAudioLanguage)
        try container.encode(preferredAnimeAudioLanguage, forKey: .preferredAnimeAudioLanguage)
        try container.encode(inAppPlayer, forKey: .inAppPlayer)
        try container.encode(showScheduleTab, forKey: .showScheduleTab)
        try container.encode(showLocalScheduleTime, forKey: .showLocalScheduleTime)
        try container.encode(ScheduleMode.sanitizedRawValue(defaultScheduleMode), forKey: .defaultScheduleMode)
        try container.encode(ScheduleWindow.sanitizedDays(scheduleWindowDays), forKey: .scheduleWindowDays)
        try container.encodeIfPresent(
            Self.sanitizedLocalNotificationSubscriptions(localNotificationSubscriptions),
            forKey: .localNotificationSubscriptions
        )
        try container.encodeIfPresent(
            Self.sanitizedLocalNotificationEpisodeReminders(localNotificationEpisodeReminders),
            forKey: .localNotificationEpisodeReminders
        )
        try container.encodeIfPresent(
            Self.sanitizedLocalNotificationEpisodeLeadTime(localNotificationEpisodeLeadTime),
            forKey: .localNotificationEpisodeLeadTime
        )
        try container.encodeIfPresent(
            Self.sanitizedLocalNotificationSeasonLeadTime(localNotificationSeasonLeadTime),
            forKey: .localNotificationSeasonLeadTime
        )
        try container.encodeIfPresent(localNotificationIncludeAnimeSpecials, forKey: .localNotificationIncludeAnimeSpecials)

        try container.encode(Self.sanitizedDefaultPlaybackSpeed(defaultPlaybackSpeed), forKey: .defaultPlaybackSpeed)
        try container.encode(Self.sanitizedHoldSpeedPlayer(holdSpeedPlayer), forKey: .holdSpeedPlayer)
        try container.encode(externalPlayer, forKey: .externalPlayer)
        try container.encode(preferDownloadedMedia, forKey: .preferDownloadedMedia)
        try container.encode(alwaysLandscape, forKey: .alwaysLandscape)
        try container.encode(playerPlaybackLockEnabled, forKey: .playerPlaybackLockEnabled)
        try container.encode(aniSkipEnabled, forKey: .aniSkipEnabled)
        try container.encode(introDBEnabled, forKey: .introDBEnabled)
        try container.encode(introDBAppEnabled, forKey: .introDBAppEnabled)
        try container.encode(aniSkipAutoSkip, forKey: .aniSkipAutoSkip)
        try container.encode(skip85sEnabled, forKey: .skip85sEnabled)
        try container.encode(skip85sAlwaysVisible, forKey: .skip85sAlwaysVisible)
        try container.encode(showNextEpisodeButton, forKey: .showNextEpisodeButton)
        try container.encode(showEpisodeBrowserButton, forKey: .showEpisodeBrowserButton)
        try container.encode(showPlayerServicesButton, forKey: .showPlayerServicesButton)
        try container.encode(showNextEpisodePosterButton, forKey: .showNextEpisodePosterButton)
        try container.encode(Self.sanitizedNextEpisodeThreshold(nextEpisodeThreshold), forKey: .nextEpisodeThreshold)
        try container.encode(nextEpisodeSkipFillerEnabled, forKey: .nextEpisodeSkipFillerEnabled)
        try container.encode(playerBrightnessGestureEnabled, forKey: .playerBrightnessGestureEnabled)
        try container.encode(playerVolumeGestureEnabled, forKey: .playerVolumeGestureEnabled)
        try container.encode(playerTwoFingerTapPlayPauseEnabled, forKey: .playerTwoFingerTapPlayPauseEnabled)
        try container.encode(playerCenterTapPlayPauseEnabled, forKey: .playerCenterTapPlayPauseEnabled)
        try container.encode(playerDoubleTapSeekEnabled, forKey: .playerDoubleTapSeekEnabled)
        try container.encode(Self.sanitizedPlayerDoubleTapSeekSeconds(playerDoubleTapSeekSeconds), forKey: .playerDoubleTapSeekSeconds)
        try container.encode(playerOpenSubtitlesEnabled, forKey: .playerOpenSubtitlesEnabled)
        try container.encode(playerOpenSubtitlesAutoFallbackEnabled, forKey: .playerOpenSubtitlesAutoFallbackEnabled)
        try container.encode(playerPerformanceOverlayEnabled, forKey: .playerPerformanceOverlayEnabled)
        try container.encode(mpvForegroundFPS, forKey: .mpvForegroundFPS)
        try container.encode(mpvRenderBackend, forKey: .mpvRenderBackend)
        try container.encode(mpvMetalQualityProfile, forKey: .mpvMetalQualityProfile)
        try container.encode(mpvUpscalingMode, forKey: .mpvUpscalingMode)
        try container.encode(mpvNeuralUpscaler, forKey: .mpvNeuralUpscaler)
        try container.encode(mpvNeuralUpscalerTV, forKey: .mpvNeuralUpscalerTV)
        try container.encode(Self.sanitizedMPVPlayerSkin(mpvPlayerSkin), forKey: .mpvPlayerSkin)
        try container.encodeIfPresent(mpvPlayerSkinCustomPrimaryColor, forKey: .mpvPlayerSkinCustomPrimaryColor)
        try container.encodeIfPresent(mpvPlayerSkinCustomSecondaryColor, forKey: .mpvPlayerSkinCustomSecondaryColor)
        try container.encode(mpvPlayerSkinAnimationsEnabled, forKey: .mpvPlayerSkinAnimationsEnabled)
        try container.encode(mpvPlayerSkinTintControlsOnly, forKey: .mpvPlayerSkinTintControlsOnly)
        try container.encode(mpvPictureInPictureEnabled, forKey: .mpvPictureInPictureEnabled)
        try container.encode(mpvAppExitPictureInPictureEnabled, forKey: .mpvAppExitPictureInPictureEnabled)
        try container.encode(mpvHDRMode, forKey: .mpvHDRMode)
        try container.encode(mpvSurroundSoundEnabled, forKey: .mpvSurroundSoundEnabled)
        try container.encode(watchTogetherEnabled, forKey: .watchTogetherEnabled)
        try container.encode(smartInAppPlayerChoosingEnabled, forKey: .smartInAppPlayerChoosingEnabled)
        try container.encodeIfPresent(experimentalFeaturesEnabled, forKey: .experimentalFeaturesEnabled)
        try container.encodeIfPresent(
            Self.sanitizedExperimentalFeaturesLastChangedAt(experimentalFeaturesLastChangedAt),
            forKey: .experimentalFeaturesLastChangedAt
        )
        try container.encode(experimentalMPVPreloadEnabled, forKey: .experimentalMPVPreloadEnabled)
        try container.encode(experimentalMPVSmoothTransitionEnabled, forKey: .experimentalMPVSmoothTransitionEnabled)
        try container.encode(experimentalMPVPreloadCellularEnabled, forKey: .experimentalMPVPreloadCellularEnabled)
        try container.encode(ExperimentalFeatureState.clampedMPVPreloadWifiLimitMB(experimentalMPVPreloadWifiLimitMB), forKey: .experimentalMPVPreloadWifiLimitMB)
        try container.encode(ExperimentalFeatureState.clampedMPVPreloadCellularLimitMB(experimentalMPVPreloadCellularLimitMB), forKey: .experimentalMPVPreloadCellularLimitMB)
        try container.encode(experimentalMPVShowRemainingTime, forKey: .experimentalMPVShowRemainingTime)
        try container.encode(experimentalMPVPreciseProgress, forKey: .experimentalMPVPreciseProgress)
        try container.encode(experimentalMPVIgnoreSpecialSubtitleStyles, forKey: .experimentalMPVIgnoreSpecialSubtitleStyles)
        try container.encode(experimentalMPVPreloadAutoClear, forKey: .experimentalMPVPreloadAutoClear)
        try container.encode(experimentalICloudSyncEnabled, forKey: .experimentalICloudSyncEnabled)

        try container.encodeIfPresent(subtitleForegroundColor, forKey: .subtitleForegroundColor)
        try container.encodeIfPresent(subtitleStrokeColor, forKey: .subtitleStrokeColor)
        try container.encode(Self.sanitizedSubtitleStrokeWidth(subtitleStrokeWidth), forKey: .subtitleStrokeWidth)
        try container.encode(Self.sanitizedSubtitleFontSize(subtitleFontSize), forKey: .subtitleFontSize)
        try container.encode(Self.sanitizedSubtitleVerticalOffset(subtitleVerticalOffset), forKey: .subtitleVerticalOffset)
        try container.encode(subtitlesVisible, forKey: .subtitlesVisible)

        try container.encode(showKanzen, forKey: .showKanzen)
        try container.encodeIfPresent(hideSplashScreen, forKey: .hideSplashScreen)
        try container.encode(modeSwitchAnimationEnabled, forKey: .modeSwitchAnimationEnabled)
        try container.encode(kanzenAutoUpdateModules, forKey: .kanzenAutoUpdateModules)
        try container.encode(seasonMenu, forKey: .seasonMenu)
        try container.encode(horizontalEpisodeList, forKey: .horizontalEpisodeList)
        try container.encode(mediaDetailTitleArtworkEnabled, forKey: .mediaDetailTitleArtworkEnabled)
        try container.encode(mediaDetailAlternatePosterEnabled, forKey: .mediaDetailAlternatePosterEnabled)
        try container.encode(mediaDetailSimilarTitlesEnabled, forKey: .mediaDetailSimilarTitlesEnabled)
        try container.encode(useClassicScheduleUI, forKey: .useClassicScheduleUI)
        try container.encode(heroBannerCatalogId, forKey: .heroBannerCatalogId)
        try container.encode(homeCatalogLayoutOverrides, forKey: .homeCatalogLayoutOverrides)
        try container.encodeIfPresent(homeAnimatedBackgroundEnabled, forKey: .homeAnimatedBackgroundEnabled)
        try container.encode(Self.sanitizedHomeAnimatedBackgroundQuality(homeAnimatedBackgroundQuality), forKey: .homeAnimatedBackgroundQuality)
        try container.encode(Self.sanitizedHomeAnimatedBackgroundFrameRate(homeAnimatedBackgroundFrameRate), forKey: .homeAnimatedBackgroundFrameRate)
        try container.encode(appPerformanceOverlayEnabled, forKey: .appPerformanceOverlayEnabled)
        try container.encode(Self.sanitizedHeroBannerBehavior(heroBannerBehavior), forKey: .heroBannerBehavior)
        try container.encode(Self.sanitizedExperimentalMediaDesignPreset(experimentalMediaDesignPreset), forKey: .experimentalMediaDesignPreset)
        try container.encode(Self.sanitizedExperimentalHeroBleedLevel(experimentalHeroBleedLevel), forKey: .experimentalHeroBleedLevel)
        try container.encode(Self.sanitizedExperimentalHomeCardShape(experimentalHomeCardShape), forKey: .experimentalHomeCardShape)
        try container.encode(Self.sanitizedExperimentalMultiGradientPalette(experimentalMultiGradientPalette), forKey: .experimentalMultiGradientPalette)
        try container.encode(Self.sanitizedExperimentalHeroHeightScale(experimentalHeroHeightScale), forKey: .experimentalHeroHeightScale)
        try container.encode(Self.sanitizedExperimentalHeroBleedStrength(experimentalHeroBleedStrength), forKey: .experimentalHeroBleedStrength)
        try container.encode(Self.sanitizedExperimentalHeroFadeDistanceScale(experimentalHeroFadeDistanceScale), forKey: .experimentalHeroFadeDistanceScale)
        try container.encode(Self.sanitizedExperimentalSectionSpacingScale(experimentalSectionSpacingScale), forKey: .experimentalSectionSpacingScale)
        try container.encode(Self.sanitizedExperimentalCardRadiusScale(experimentalCardRadiusScale), forKey: .experimentalCardRadiusScale)
        try container.encode(Self.sanitizedExperimentalMediaCardScale(experimentalMediaCardScale), forKey: .experimentalMediaCardScale)
        try container.encode(Self.sanitizedExperimentalGlassStrength(experimentalGlassStrength), forKey: .experimentalGlassStrength)
        try container.encode(Self.sanitizedExperimentalGradientBaseDarkness(experimentalGradientBaseDarkness), forKey: .experimentalGradientBaseDarkness)
        try container.encode(Self.sanitizedExperimentalGradientAccentIntensity(experimentalGradientAccentIntensity), forKey: .experimentalGradientAccentIntensity)
        try container.encode(Self.sanitizedExperimentalGradientScrollMotion(experimentalGradientScrollMotion), forKey: .experimentalGradientScrollMotion)
        try container.encode(experimentalGradientUseCustomColors, forKey: .experimentalGradientUseCustomColors)
        try container.encodeIfPresent(experimentalGradientColorA, forKey: .experimentalGradientColorA)
        try container.encodeIfPresent(experimentalGradientColorB, forKey: .experimentalGradientColorB)
        try container.encodeIfPresent(experimentalGradientColorC, forKey: .experimentalGradientColorC)
        try container.encode(Self.sanitizedAtmosphereStyle(atmosphereStyle), forKey: .atmosphereStyle)
        try container.encode(Self.sanitizedAtmosphereSolidColorSource(atmosphereSolidColorSource), forKey: .atmosphereSolidColorSource)
        try container.encodeIfPresent(atmosphereSolidColor, forKey: .atmosphereSolidColor)
        try container.encode(Self.sanitizedAtmosphereStyle(readerAtmosphereStyle), forKey: .readerAtmosphereStyle)
        try container.encode(Self.sanitizedAtmosphereSolidColorSource(readerAtmosphereSolidColorSource), forKey: .readerAtmosphereSolidColorSource)
        try container.encodeIfPresent(readerAtmosphereSolidColor, forKey: .readerAtmosphereSolidColor)
        try container.encode(Self.sanitizedMediaDetailElementOrder(mediaDetailElementOrder), forKey: .mediaDetailElementOrder)
        try container.encode(Self.sanitizedMediaDetailHiddenElements(mediaDetailHiddenElements), forKey: .mediaDetailHiddenElements)
        try container.encode(Self.sanitizedReaderDetailElementOrder(readerDetailElementOrder), forKey: .readerDetailElementOrder)
        try container.encode(Self.sanitizedReaderDetailHiddenElements(readerDetailHiddenElements), forKey: .readerDetailHiddenElements)
        try container.encode(mediaColumnsPortrait, forKey: .mediaColumnsPortrait)
        try container.encode(mediaColumnsLandscape, forKey: .mediaColumnsLandscape)

        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(Self.sanitizedKanzenReaderMode(kanzenReaderMode), forKey: .kanzenReaderMode)
        try container.encode(Self.sanitizedKanzenReaderModeOverrides(kanzenReaderModeOverrides), forKey: .kanzenReaderModeOverrides)
        try container.encode(readerDownsampleImages, forKey: .readerDownsampleImages)
        try container.encode(readerCropBorders, forKey: .readerCropBorders)
        try container.encode(readerDisableQuickActions, forKey: .readerDisableQuickActions)
        try container.encode(readerDisableDoubleTap, forKey: .readerDisableDoubleTap)
        try container.encode(readerLiveText, forKey: .readerLiveText)
        try container.encode(readerHideBarsOnSwipe, forKey: .readerHideBarsOnSwipe)
        try container.encode(Self.sanitizedReaderBackgroundColor(readerBackgroundColor), forKey: .readerBackgroundColor)
        try container.encode(Self.sanitizedReaderOrientation(readerOrientation), forKey: .readerOrientation)
        try container.encode(Self.sanitizedReaderTapZones(readerTapZones), forKey: .readerTapZones)
        try container.encode(readerInvertTapZones, forKey: .readerInvertTapZones)
        try container.encode(readerAnimatePageTransitions, forKey: .readerAnimatePageTransitions)
        try container.encode(readerUpscaleImages, forKey: .readerUpscaleImages)
        try container.encode(Self.sanitizedReaderUpscaleMaxHeight(readerUpscaleMaxHeight), forKey: .readerUpscaleMaxHeight)
        try container.encode(readerUpscaleModelName, forKey: .readerUpscaleModelName)
        try container.encode(Self.sanitizedReaderPagesToPreload(readerPagesToPreload), forKey: .readerPagesToPreload)
        try container.encode(Self.sanitizedReaderPagedPageLayout(readerPagedPageLayout), forKey: .readerPagedPageLayout)
        try container.encode(readerPagedPageOffset, forKey: .readerPagedPageOffset)
        try container.encode(Self.sanitizedReaderPagedPageOffsetOverrides(readerPagedPageOffsetOverrides), forKey: .readerPagedPageOffsetOverrides)
        try container.encode(readerSplitWideImages, forKey: .readerSplitWideImages)
        try container.encode(readerReverseSplitOrder, forKey: .readerReverseSplitOrder)
        try container.encode(readerVerticalInfiniteScroll, forKey: .readerVerticalInfiniteScroll)
        try container.encode(readerPillarbox, forKey: .readerPillarbox)
        try container.encode(Self.sanitizedReaderPillarboxAmount(readerPillarboxAmount), forKey: .readerPillarboxAmount)
        try container.encode(Self.sanitizedReaderPillarboxOrientation(readerPillarboxOrientation), forKey: .readerPillarboxOrientation)
        try container.encode(readerOrientationLockEnabled, forKey: .readerOrientationLockEnabled)
        try container.encode(Self.sanitizedReaderOrientationLockMask(readerOrientationLockMask), forKey: .readerOrientationLockMask)
        try container.encode(Self.sanitizedReaderReadThresholdPercent(readerReadThresholdPercent), forKey: .readerReadThresholdPercent)

        try container.encode(Self.sanitizedReaderFontSize(readerFontSize), forKey: .readerFontSize)
        try container.encode(readerFontFamily, forKey: .readerFontFamily)
        try container.encode(readerFontWeight, forKey: .readerFontWeight)
        try container.encode(Self.sanitizedReaderColorPreset(readerColorPreset), forKey: .readerColorPreset)
        try container.encode(readerTextAlignment, forKey: .readerTextAlignment)
        try container.encode(Self.sanitizedReaderLineSpacing(readerLineSpacing), forKey: .readerLineSpacing)
        try container.encode(Self.sanitizedReaderMargin(readerMargin), forKey: .readerMargin)

        try container.encode(autoClearCacheEnabled, forKey: .autoClearCacheEnabled)
        try container.encode(Self.sanitizedAutoClearCacheThresholdMB(autoClearCacheThresholdMB), forKey: .autoClearCacheThresholdMB)
        try container.encode(Self.sanitizedHighQualityThreshold(highQualityThreshold), forKey: .highQualityThreshold)
        try container.encode(backgroundHLSPipelineEnabled, forKey: .backgroundHLSPipelineEnabled)
        try container.encode(readerDownloadsBackgroundEnabled, forKey: .readerDownloadsBackgroundEnabled)
        try container.encode(readerDownloadsWifiOnly, forKey: .readerDownloadsWifiOnly)
        try container.encode(Self.sanitizedReaderDownloadsParallelLimit(readerDownloadsParallelLimit), forKey: .readerDownloadsParallelLimit)
        try container.encode(autoUpdateServicesEnabled, forKey: .autoUpdateServicesEnabled)
        try container.encode(servicesAutoModeEnabled, forKey: .servicesAutoModeEnabled)
        try container.encode(servicesAutoSelectEpisodesEnabled, forKey: .servicesAutoSelectEpisodesEnabled)
        try container.encode(servicesAutoModeErrorIntelligenceEnabled, forKey: .servicesAutoModeErrorIntelligenceEnabled)
        try container.encode(Self.sanitizedStringList(servicesAutoModeSourceIds), forKey: .servicesAutoModeSourceIds)
        try container.encode(Self.sanitizedStringList(servicesAutoModeSourceOrderIds), forKey: .servicesAutoModeSourceOrderIds)
        try container.encode(AutoModeQualityPreference.sanitizedRawValue(servicesAutoModeQualityPreference), forKey: .servicesAutoModeQualityPreference)
        try container.encode(Self.sanitizedServicesResultMinimumSimilarity(servicesResultMinimumSimilarity), forKey: .servicesResultMinimumSimilarity)
        try container.encode(servicesDropMismatchedResults, forKey: .servicesDropMismatchedResults)
        try container.encode(servicesStremioStyleSheetEnabled, forKey: .servicesStremioStyleSheetEnabled)
        try container.encode(StreamLanguageFilter.sanitizedLanguageList(servicesIncludedStreamLanguages), forKey: .servicesIncludedStreamLanguages)
        try container.encode(StreamLanguageFilter.sanitizedLanguageList(servicesHiddenStreamLanguages), forKey: .servicesHiddenStreamLanguages)
        try container.encode(servicesHideStreamsWithoutLanguageData, forKey: .servicesHideStreamsWithoutLanguageData)
        try container.encode(servicesAssumeOriginalAudio, forKey: .servicesAssumeOriginalAudio)
        try container.encode(servicesTreatDubbedAnimeAsEnglish, forKey: .servicesTreatDubbedAnimeAsEnglish)
        try container.encode(StreamLanguageFilter.sanitizedQualityHeights(servicesHiddenStreamQualities), forKey: .servicesHiddenStreamQualities)
        try container.encode(servicesHideStreamsWithoutDetectedQuality, forKey: .servicesHideStreamsWithoutDetectedQuality)
        if let servicesExtraRulesSourceIds {
            try container.encode(
                StreamLanguageFilter.sanitizedExtraRulesSourceIds(servicesExtraRulesSourceIds),
                forKey: .servicesExtraRulesSourceIds
            )
        }
        try container.encode(githubReleaseAutoCheckEnabled, forKey: .githubReleaseAutoCheckEnabled)
        try container.encode(githubReleaseUpdateAvailable, forKey: .githubReleaseUpdateAvailable)
        try container.encode(githubReleaseLatestVersion, forKey: .githubReleaseLatestVersion)
        try container.encode(githubReleaseURL, forKey: .githubReleaseURL)
        try container.encode(githubReleaseShowAlertPending, forKey: .githubReleaseShowAlertPending)
        try container.encode(githubReleaseLastPromptedVersion, forKey: .githubReleaseLastPromptedVersion)
        try container.encode(filterHorrorContent, forKey: .filterHorrorContent)
        try container.encode(Self.sanitizedSimilarityAlgorithm(selectedSimilarityAlgorithm), forKey: .selectedSimilarityAlgorithm)
        try container.encode(performanceModeEnabled, forKey: .performanceModeEnabled)
        try container.encode(performanceModeSkipAniListTraversalForAnimeDetails, forKey: .performanceModeSkipAniListTraversalForAnimeDetails)
        try container.encode(performanceModeFastAnimeCatalogOverrides.filter { PerformanceModeSettings.animeCatalogIds.contains($0.key) }, forKey: .performanceModeFastAnimeCatalogOverrides)
        try container.encode(kanzenHomeSelectedSourceID, forKey: .kanzenHomeSelectedSourceID)
        try container.encode(kanzenRecentSourceSearches, forKey: .kanzenRecentSourceSearches)

        if hasCollections {
            try container.encode(Self.sanitizedCollections(collections), forKey: .collections)
        }
        if hasProgressData {
            try container.encode(Self.sanitizedProgressData(progressData), forKey: .progressData)
        }
        if hasTrackerState {
            try container.encode(trackerState, forKey: .trackerState)
        }
        if hasCatalogs {
            try container.encode(catalogs, forKey: .catalogs)
        }
        if hasServices {
            try container.encode(services, forKey: .services)
        }
        try container.encodeIfPresent(stremioAddons, forKey: .stremioAddons)
        try container.encodeIfPresent(skyStream, forKey: .skyStream)
        try container.encodeIfPresent(nuvioPlugins, forKey: .nuvioPlugins)
        if hasMangaCollections {
            try container.encode(mangaCollections, forKey: .mangaCollections)
        }
        if hasMangaReadingProgress {
            try container.encode(mangaReadingProgress, forKey: .mangaReadingProgress)
        }
        if hasMangaCatalogs {
            try container.encode(mangaCatalogs, forKey: .mangaCatalogs)
        }
        if hasCustomCatalogs || !customCatalogs.isEmpty {
            try container.encode(customCatalogs, forKey: .customCatalogs)
        }
        if hasKanzenModules {
            try container.encode(kanzenModules, forKey: .kanzenModules)
        }
        try container.encodeIfPresent(readerExtensionsState?.sanitized(), forKey: .readerExtensionsState)
        try container.encode(searchHistory, forKey: .searchHistory)
        try container.encode(
            Self.sanitizedRecommendationCache(recommendationCache),
            forKey: .recommendationCache
        )
        if hasUserRatings {
            try container.encode(Self.sanitizedUserRatings(userRatings), forKey: .userRatings)
            try container.encode(Self.sanitizedUserRatingNotes(userRatingNotes), forKey: .userRatingNotes)
        }
        try container.encodeIfPresent(mediaStateSettings, forKey: .mediaStateSettings)
        let safeServicesSettings = Self.servicesSettingsForExperimentalCloudSync(
            servicesSettings
        )
        try container.encodeIfPresent(safeServicesSettings, forKey: .servicesSettings)
        try container.encode(
            servicesSettingsWereCaptured && safeServicesSettings != nil,
            forKey: .servicesSettingsWereCaptured
        )
        try container.encodeIfPresent(sharesServices, forKey: .sharesServices)
        try container.encodeIfPresent(profiles, forKey: .profiles)
        try container.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
        try container.encodeIfPresent(skyStreamSharedPayloads, forKey: .skyStreamSharedPayloads)
        try container.encodeIfPresent(nuvioSharedPayloads, forKey: .nuvioSharedPayloads)
    }

    init(
        version: String = BackupData.currentCloudSchemaVersion,
        createdDate: Date,
        accentColor: Data? = nil,
        settingsGradientColor: Data? = nil,
        readerAccentColor: Data? = nil,
        tmdbLanguage: String,
        selectedAppearance: String,
        readerSelectedAppearance: String = "system",
        readerGlobalAppearanceEnabled: Bool = true,
        readerSettingsGradientColor: Data? = nil,
        enableSubtitlesByDefault: Bool,
        defaultSubtitleLanguage: String,
        playerSubtitleAppearanceEnabled: Bool,

        preferredAutoAudioLanguage: String,
        preferredAnimeAudioLanguage: String,
        inAppPlayer: String,
        showScheduleTab: Bool,
        showLocalScheduleTime: Bool,
        defaultScheduleMode: String = ScheduleMode.anime.rawValue,
        scheduleWindowDays: Int = ScheduleWindow.defaultValue.rawValue,
        localNotificationSubscriptions: String? = nil,
        localNotificationEpisodeReminders: String? = nil,
        localNotificationEpisodeLeadTime: Int? = nil,
        localNotificationSeasonLeadTime: Int? = nil,
        localNotificationIncludeAnimeSpecials: Bool? = nil,

        defaultPlaybackSpeed: Double = 1.0,
        holdSpeedPlayer: Double = 2.0,
        externalPlayer: String = "none",
        preferDownloadedMedia: Bool = false,
        alwaysLandscape: Bool = false,
        playerPlaybackLockEnabled: Bool = PlayerPlaybackLockSettings.defaultEnabled,
        aniSkipEnabled: Bool = true,
        introDBEnabled: Bool = true,
        introDBAppEnabled: Bool = true,
        aniSkipAutoSkip: Bool = false,
        skip85sEnabled: Bool = false,
        skip85sAlwaysVisible: Bool = false,
        showNextEpisodeButton: Bool = true,
        showEpisodeBrowserButton: Bool = true,
        showPlayerServicesButton: Bool = false,
        showNextEpisodePosterButton: Bool = false,
        nextEpisodeThreshold: Double = 0.90,
        nextEpisodeSkipFillerEnabled: Bool = NextEpisodeFillerSettings.defaultEnabled,
        playerBrightnessGestureEnabled: Bool = false,
        playerVolumeGestureEnabled: Bool = false,
        playerTwoFingerTapPlayPauseEnabled: Bool = true,
        playerCenterTapPlayPauseEnabled: Bool = true,
        playerDoubleTapSeekEnabled: Bool = true,
        playerDoubleTapSeekSeconds: Double = 10.0,
        playerOpenSubtitlesEnabled: Bool = false,
        playerOpenSubtitlesAutoFallbackEnabled: Bool = true,
        playerPerformanceOverlayEnabled: Bool = false,
        mpvForegroundFPS: Int = 30,
        mpvRenderBackend: String = MPVRenderBackend.defaultBackend.rawValue,
        mpvMetalQualityProfile: String = MPVMetalQualityProfile.defaultProfile.rawValue,
        mpvUpscalingMode: String = MPVUpscalingMode.defaultMode.rawValue,
        mpvNeuralUpscaler: String = MPVNeuralUpscaler.defaultUpscaler.rawValue,
        mpvNeuralUpscalerTV: String = MPVNeuralUpscaler.defaultUpscaler.rawValue,
        mpvPlayerSkin: String = MPVPlayerSkin.defaultSkin.rawValue,
        mpvPlayerSkinCustomPrimaryColor: Data? = nil,
        mpvPlayerSkinCustomSecondaryColor: Data? = nil,
        mpvPlayerSkinAnimationsEnabled: Bool = MPVPlayerSkinSettings.defaultAnimationsEnabled,
        mpvPlayerSkinTintControlsOnly: Bool = MPVPlayerSkinSettings.defaultTintControlsOnly,
        mpvPictureInPictureEnabled: Bool = true,
        mpvAppExitPictureInPictureEnabled: Bool = false,
        mpvHDRMode: String = MPVHDRMode.defaultMode.rawValue,
        mpvSurroundSoundEnabled: Bool = true,
        watchTogetherEnabled: Bool = WatchTogetherSettings.defaultEnabled,
        smartInAppPlayerChoosingEnabled: Bool = false,
        experimentalFeaturesEnabled: Bool? = nil,
        experimentalFeaturesLastChangedAt: Double? = nil,
        experimentalMPVPreloadEnabled: Bool = true,
        experimentalMPVSmoothTransitionEnabled: Bool = true,
        experimentalMPVPreloadCellularEnabled: Bool = false,
        experimentalMPVPreloadWifiLimitMB: Int = ExperimentalFeatureState.mpvPreloadWifiDefaultLimitMB,
        experimentalMPVPreloadCellularLimitMB: Int = ExperimentalFeatureState.mpvPreloadCellularDefaultLimitMB,
        experimentalMPVShowRemainingTime: Bool = true,
        experimentalMPVPreciseProgress: Bool = true,
        experimentalMPVIgnoreSpecialSubtitleStyles: Bool = false,
        experimentalMPVPreloadAutoClear: Bool = true,
        experimentalICloudSyncEnabled: Bool = false,

        subtitleForegroundColor: Data? = nil,
        subtitleStrokeColor: Data? = nil,
        subtitleStrokeWidth: Double = 1.0,
        subtitleFontSize: Double = 30.0,
        subtitleVerticalOffset: Double = -6.0,
        subtitlesVisible: Bool = false,

        showKanzen: Bool = false,
        hideSplashScreen: Bool? = nil,
        modeSwitchAnimationEnabled: Bool = ModeSwitchAnimationSettings.defaultEnabled,
        kanzenAutoUpdateModules: Bool = true,
        seasonMenu: Bool = false,
        horizontalEpisodeList: Bool = false,
        mediaDetailTitleArtworkEnabled: Bool = MediaDetailTitleArtworkSettings.defaultEnabled,
        mediaDetailAlternatePosterEnabled: Bool = MediaDetailAlternatePosterSettings.defaultEnabled,
        mediaDetailSimilarTitlesEnabled: Bool = MediaDetailSimilarTitlesSettings.defaultEnabled,
        useClassicScheduleUI: Bool = false,
        heroBannerCatalogId: String = "trending",
        heroBannerBehavior: String = HeroBannerBehavior.defaultValue.rawValue,
        homeCatalogLayoutOverrides: String = "",
        homeAnimatedBackgroundEnabled: Bool? = nil,
        homeAnimatedBackgroundQuality: String = HomeAnimatedBackgroundQuality.defaultValue.rawValue,
        homeAnimatedBackgroundFrameRate: String = HomeAnimatedBackgroundFrameRate.defaultValue.rawValue,
        appPerformanceOverlayEnabled: Bool = AppPerformanceOverlaySettings.defaultEnabled,
        experimentalMediaDesignPreset: String = ExperimentalMediaDesignPreset.defaultValue.rawValue,
        experimentalHeroBleedLevel: String = ExperimentalHeroBleedLevel.defaultValue.rawValue,
        experimentalHomeCardShape: String = ExperimentalHomeCardShape.defaultValue.rawValue,
        experimentalMultiGradientPalette: String = ExperimentalMultiGradientPalette.defaultValue.rawValue,
        experimentalHeroHeightScale: Double = ExperimentalVisualTuning.defaultHeroHeightScale,
        experimentalHeroBleedStrength: Double = ExperimentalVisualTuning.defaultHeroBleedStrength,
        experimentalHeroFadeDistanceScale: Double = ExperimentalVisualTuning.defaultHeroFadeDistanceScale,
        experimentalSectionSpacingScale: Double = ExperimentalVisualTuning.defaultSectionSpacingScale,
        experimentalCardRadiusScale: Double = ExperimentalVisualTuning.defaultCardRadiusScale,
        experimentalMediaCardScale: Double = ExperimentalVisualTuning.defaultMediaCardScale,
        experimentalGlassStrength: Double = ExperimentalVisualTuning.defaultGlassStrength,
        experimentalGradientBaseDarkness: Double = ExperimentalVisualTuning.defaultGradientBaseDarkness,
        experimentalGradientAccentIntensity: Double = ExperimentalVisualTuning.defaultGradientAccentIntensity,
        experimentalGradientScrollMotion: Double = ExperimentalVisualTuning.defaultGradientScrollMotion,
        experimentalGradientUseCustomColors: Bool = false,
        experimentalGradientColorA: Data? = nil,
        experimentalGradientColorB: Data? = nil,
        experimentalGradientColorC: Data? = nil,
        atmosphereStyle: String = AtmosphereStyle.gradient.rawValue,
        atmosphereSolidColorSource: String = AtmosphereSolidColorSource.dominant.rawValue,
        atmosphereSolidColor: Data? = nil,
        readerAtmosphereStyle: String = AtmosphereStyle.gradient.rawValue,
        readerAtmosphereSolidColorSource: String = AtmosphereSolidColorSource.dominant.rawValue,
        readerAtmosphereSolidColor: Data? = nil,
        mediaDetailElementOrder: String = MediaDetailElement.defaultOrderRawValue,
        mediaDetailHiddenElements: String = "",
        readerDetailElementOrder: String = ReaderDetailElement.defaultOrderRawValue,
        readerDetailHiddenElements: String = "",
        mediaColumnsPortrait: Int = 3,
        mediaColumnsLandscape: Int = 5,

        readingMode: Int = 2,
        kanzenReaderMode: String = "webtoon",
        kanzenReaderModeOverrides: [String: String] = [:],
        readerDownsampleImages: Bool = true,
        readerCropBorders: Bool = false,
        readerDisableQuickActions: Bool = false,
        readerDisableDoubleTap: Bool = false,
        readerLiveText: Bool = false,
        readerHideBarsOnSwipe: Bool = false,
        readerBackgroundColor: String = "black",
        readerOrientation: String = "device",
        readerTapZones: String = "disabled",
        readerInvertTapZones: Bool = false,
        readerAnimatePageTransitions: Bool = true,
        readerUpscaleImages: Bool = false,
        readerUpscaleMaxHeight: Int = 2000,
        readerUpscaleModelName: String = "None",
        readerPagesToPreload: Int = 3,
        readerPagedPageLayout: String = "single",
        readerPagedPageOffset: Bool = false,
        readerPagedPageOffsetOverrides: [String: Bool] = [:],
        readerSplitWideImages: Bool = false,
        readerReverseSplitOrder: Bool = false,
        readerVerticalInfiniteScroll: Bool = true,
        readerPillarbox: Bool = false,
        readerPillarboxAmount: Double = 15,
        readerPillarboxOrientation: String = "both",
        readerOrientationLockEnabled: Bool = false,
        readerOrientationLockMask: String = "all",
        readerReadThresholdPercent: Double = 80,

        readerFontSize: Double = 16,
        readerFontFamily: String = "-apple-system",
        readerFontWeight: String = "normal",
        readerColorPreset: Int = 0,
        readerTextAlignment: String = "left",
        readerLineSpacing: Double = 1.6,
        readerMargin: Double = 4,

        autoClearCacheEnabled: Bool = false,
        autoClearCacheThresholdMB: Double = 500,
        highQualityThreshold: Double = 0.9,
        backgroundHLSPipelineEnabled: Bool = false,
        readerDownloadsBackgroundEnabled: Bool = true,
        readerDownloadsWifiOnly: Bool = false,
        readerDownloadsParallelLimit: Int = 2,
        autoUpdateServicesEnabled: Bool = true,
        servicesAutoModeEnabled: Bool = AutoModeSettings.defaultEnabled,
        servicesAutoSelectEpisodesEnabled: Bool = false,
        servicesAutoModeErrorIntelligenceEnabled: Bool = AutoModeErrorIntelligenceSettings.defaultEnabled,
        servicesAutoModeSourceIds: [String] = [],
        servicesAutoModeSourceOrderIds: [String] = [],
        servicesAutoModeQualityPreference: String = AutoModeQualityPreference.defaultPreference.rawValue,
        servicesResultMinimumSimilarity: Double = ServicesResultRankingSettings.defaultMinimumSimilarity,
        servicesDropMismatchedResults: Bool = ServicesResultRankingSettings.defaultDropMismatchedResults,
        servicesStremioStyleSheetEnabled: Bool = ServicesSheetPresentationSettings.defaultStremioStyleEnabled,
        servicesIncludedStreamLanguages: [String] = [],
        servicesHiddenStreamLanguages: [String] = [],
        servicesHideStreamsWithoutLanguageData: Bool = false,
        servicesAssumeOriginalAudio: Bool = false,
        servicesTreatDubbedAnimeAsEnglish: Bool = false,
        servicesHiddenStreamQualities: [Int] = [],
        servicesHideStreamsWithoutDetectedQuality: Bool = false,
        servicesExtraRulesSourceIds: [String]? = nil,
        githubReleaseAutoCheckEnabled: Bool = true,
        githubReleaseUpdateAvailable: Bool = false,
        githubReleaseLatestVersion: String = "",
        githubReleaseURL: String = "",
        githubReleaseShowAlertPending: Bool = false,
        githubReleaseLastPromptedVersion: String = "",
        filterHorrorContent: Bool = false,
        selectedSimilarityAlgorithm: String = SimilarityAlgorithm.hybrid.rawValue,
        performanceModeEnabled: Bool = PerformanceModeSettings.defaultEnabled,
        performanceModeSkipAniListTraversalForAnimeDetails: Bool = false,
        performanceModeFastAnimeCatalogOverrides: [String: Bool] = [:],
        kanzenHomeSelectedSourceID: String = "",
        kanzenRecentSourceSearches: [String] = [],

        collections: [BackupCollection] = [],
        progressData: ProgressData = ProgressData(),
        trackerState: TrackerState = TrackerState(),
        catalogs: [Catalog] = [],
        services: [BackupService] = [],
        stremioAddons: [BackupStremioAddon]? = nil,
        skyStream: SkyStreamBackupSnapshot? = nil,
        nuvioPlugins: NuvioStoredPluginsState? = nil,
        mangaCollections: [BackupMangaCollection] = [],
        mangaReadingProgress: [String: MangaProgress] = [:],
        mangaCatalogs: [MangaCatalog] = [],
        customCatalogs: [KanzenCustomCatalog] = [],
        kanzenModules: [BackupKanzenModule] = [],
        readerExtensionsState: BackupReaderExtensionState? = nil,
        aidokuState: BackupAidokuState? = nil,
        searchHistory: BackupSearchHistory = BackupSearchHistory(),
        recommendationCache: [TMDBSearchResult] = [],
        userRatings: [String: Double] = [:],
        userRatingNotes: [String: String] = [:],
        mediaStateSettings: [String: Data]? = nil,
        collectionsPresent: Bool = true,
        progressDataPresent: Bool = true,
        trackerStatePresent: Bool = true,
        catalogsPresent: Bool = true,
        servicesPresent: Bool = true,
        mangaCollectionsPresent: Bool = true,
        mangaReadingProgressPresent: Bool = true,
        mangaCatalogsPresent: Bool = true,
        customCatalogsPresent: Bool = true,
        kanzenModulesPresent: Bool = true,
        userRatingsPresent: Bool = true
    ) {
        self.version = version
        self.createdDate = createdDate
        self.accentColor = accentColor
        self.settingsGradientColor = settingsGradientColor
        self.readerAccentColor = readerAccentColor
        self.tmdbLanguage = tmdbLanguage
        self.selectedAppearance = Self.sanitizedAppearance(selectedAppearance)
        self.readerSelectedAppearance = Self.sanitizedAppearance(readerSelectedAppearance)
        self.readerGlobalAppearanceEnabled = readerGlobalAppearanceEnabled
        self.readerSettingsGradientColor = readerSettingsGradientColor
        self.enableSubtitlesByDefault = enableSubtitlesByDefault
        self.defaultSubtitleLanguage = defaultSubtitleLanguage
        self.playerSubtitleAppearanceEnabled = playerSubtitleAppearanceEnabled

        self.preferredAutoAudioLanguage = preferredAutoAudioLanguage
        self.preferredAnimeAudioLanguage = preferredAnimeAudioLanguage
        self.inAppPlayer = Settings.normalizedInAppPlayer(inAppPlayer)
        self.showScheduleTab = showScheduleTab
        self.showLocalScheduleTime = showLocalScheduleTime
        self.defaultScheduleMode = ScheduleMode.sanitizedRawValue(defaultScheduleMode)
        self.scheduleWindowDays = ScheduleWindow.sanitizedDays(scheduleWindowDays)
        self.localNotificationSubscriptions = Self.sanitizedLocalNotificationSubscriptions(
            localNotificationSubscriptions
        )
        self.localNotificationEpisodeReminders = Self.sanitizedLocalNotificationEpisodeReminders(
            localNotificationEpisodeReminders
        )
        self.localNotificationEpisodeLeadTime = Self.sanitizedLocalNotificationEpisodeLeadTime(
            localNotificationEpisodeLeadTime
        )
        self.localNotificationSeasonLeadTime = Self.sanitizedLocalNotificationSeasonLeadTime(
            localNotificationSeasonLeadTime
        )
        self.localNotificationIncludeAnimeSpecials = localNotificationIncludeAnimeSpecials

        self.defaultPlaybackSpeed = Self.sanitizedDefaultPlaybackSpeed(defaultPlaybackSpeed)
        self.holdSpeedPlayer = Self.sanitizedHoldSpeedPlayer(holdSpeedPlayer)
        self.externalPlayer = externalPlayer
        self.preferDownloadedMedia = preferDownloadedMedia
        self.alwaysLandscape = alwaysLandscape
        self.playerPlaybackLockEnabled = playerPlaybackLockEnabled
        self.aniSkipEnabled = aniSkipEnabled
        self.introDBEnabled = introDBEnabled
        self.introDBAppEnabled = introDBAppEnabled
        self.aniSkipAutoSkip = aniSkipAutoSkip
        self.skip85sEnabled = skip85sEnabled
        self.skip85sAlwaysVisible = skip85sAlwaysVisible
        self.showNextEpisodeButton = showNextEpisodeButton
        self.showEpisodeBrowserButton = showEpisodeBrowserButton
        self.showPlayerServicesButton = showPlayerServicesButton
        self.showNextEpisodePosterButton = showNextEpisodePosterButton
        self.nextEpisodeThreshold = Self.sanitizedNextEpisodeThreshold(nextEpisodeThreshold)
        self.nextEpisodeSkipFillerEnabled = nextEpisodeSkipFillerEnabled
        self.playerBrightnessGestureEnabled = playerBrightnessGestureEnabled
        self.playerVolumeGestureEnabled = playerVolumeGestureEnabled
        self.playerTwoFingerTapPlayPauseEnabled = playerTwoFingerTapPlayPauseEnabled
        self.playerCenterTapPlayPauseEnabled = playerCenterTapPlayPauseEnabled
        self.playerDoubleTapSeekEnabled = playerDoubleTapSeekEnabled
        self.playerDoubleTapSeekSeconds = Self.sanitizedPlayerDoubleTapSeekSeconds(playerDoubleTapSeekSeconds)
        self.playerOpenSubtitlesEnabled = playerOpenSubtitlesEnabled
        self.playerOpenSubtitlesAutoFallbackEnabled = playerOpenSubtitlesAutoFallbackEnabled
        self.playerPerformanceOverlayEnabled = playerPerformanceOverlayEnabled
        self.mpvForegroundFPS = Self.sanitizedMPVForegroundFPS(mpvForegroundFPS)
        self.mpvRenderBackend = Self.sanitizedMPVRenderBackend(mpvRenderBackend)
        self.mpvMetalQualityProfile = Self.sanitizedMPVMetalQualityProfile(mpvMetalQualityProfile)
        self.mpvUpscalingMode = Self.sanitizedMPVUpscalingMode(mpvUpscalingMode)
        self.mpvNeuralUpscaler = Self.sanitizedMPVNeuralUpscaler(mpvNeuralUpscaler)
        self.mpvNeuralUpscalerTV = Self.sanitizedMPVNeuralUpscaler(mpvNeuralUpscalerTV)
        self.mpvPlayerSkin = Self.sanitizedMPVPlayerSkin(mpvPlayerSkin)
        self.mpvPlayerSkinCustomPrimaryColor = mpvPlayerSkinCustomPrimaryColor
        self.mpvPlayerSkinCustomSecondaryColor = mpvPlayerSkinCustomSecondaryColor
        self.mpvPlayerSkinAnimationsEnabled = mpvPlayerSkinAnimationsEnabled
        self.mpvPlayerSkinTintControlsOnly = mpvPlayerSkinTintControlsOnly
        self.mpvPictureInPictureEnabled = mpvPictureInPictureEnabled
        self.mpvAppExitPictureInPictureEnabled = mpvAppExitPictureInPictureEnabled
        self.mpvHDRMode = MPVHDRMode(rawValue: mpvHDRMode)?.rawValue ?? MPVHDRMode.defaultMode.rawValue
        self.mpvSurroundSoundEnabled = mpvSurroundSoundEnabled
        self.watchTogetherEnabled = watchTogetherEnabled
        self.smartInAppPlayerChoosingEnabled = smartInAppPlayerChoosingEnabled
        self.experimentalFeaturesEnabled = experimentalFeaturesEnabled
        self.experimentalFeaturesLastChangedAt = Self.sanitizedExperimentalFeaturesLastChangedAt(
            experimentalFeaturesLastChangedAt
        )
        self.experimentalMPVPreloadEnabled = experimentalMPVPreloadEnabled
        self.experimentalMPVSmoothTransitionEnabled = experimentalMPVSmoothTransitionEnabled
        self.experimentalMPVPreloadCellularEnabled = experimentalMPVPreloadCellularEnabled
        self.experimentalMPVPreloadWifiLimitMB = ExperimentalFeatureState.clampedMPVPreloadWifiLimitMB(experimentalMPVPreloadWifiLimitMB)
        self.experimentalMPVPreloadCellularLimitMB = ExperimentalFeatureState.clampedMPVPreloadCellularLimitMB(experimentalMPVPreloadCellularLimitMB)
        self.experimentalMPVShowRemainingTime = experimentalMPVShowRemainingTime
        self.experimentalMPVPreciseProgress = experimentalMPVPreciseProgress
        self.experimentalMPVIgnoreSpecialSubtitleStyles = experimentalMPVIgnoreSpecialSubtitleStyles
        self.experimentalMPVPreloadAutoClear = experimentalMPVPreloadAutoClear
        self.experimentalICloudSyncEnabled = experimentalICloudSyncEnabled

        self.subtitleForegroundColor = subtitleForegroundColor
        self.subtitleStrokeColor = subtitleStrokeColor
        self.subtitleStrokeWidth = Self.sanitizedSubtitleStrokeWidth(subtitleStrokeWidth)
        self.subtitleFontSize = Self.sanitizedSubtitleFontSize(subtitleFontSize)
        self.subtitleVerticalOffset = Self.sanitizedSubtitleVerticalOffset(subtitleVerticalOffset)
        self.subtitlesVisible = subtitlesVisible

        self.showKanzen = showKanzen
        self.hideSplashScreen = hideSplashScreen
        self.modeSwitchAnimationEnabled = modeSwitchAnimationEnabled
        self.kanzenAutoUpdateModules = kanzenAutoUpdateModules
        self.seasonMenu = seasonMenu
        self.horizontalEpisodeList = horizontalEpisodeList
        self.mediaDetailTitleArtworkEnabled = mediaDetailTitleArtworkEnabled
        self.mediaDetailAlternatePosterEnabled = mediaDetailAlternatePosterEnabled
        self.mediaDetailSimilarTitlesEnabled = mediaDetailSimilarTitlesEnabled
        self.useClassicScheduleUI = useClassicScheduleUI
        self.heroBannerCatalogId = Self.sanitizedNonEmptyString(heroBannerCatalogId, defaultValue: "trending")
        self.heroBannerBehavior = Self.sanitizedHeroBannerBehavior(heroBannerBehavior)
        self.homeCatalogLayoutOverrides = homeCatalogLayoutOverrides
        self.homeAnimatedBackgroundEnabled = homeAnimatedBackgroundEnabled
        self.homeAnimatedBackgroundQuality = Self.sanitizedHomeAnimatedBackgroundQuality(homeAnimatedBackgroundQuality)
        self.homeAnimatedBackgroundFrameRate = Self.sanitizedHomeAnimatedBackgroundFrameRate(homeAnimatedBackgroundFrameRate)
        self.appPerformanceOverlayEnabled = appPerformanceOverlayEnabled
        self.experimentalMediaDesignPreset = Self.sanitizedExperimentalMediaDesignPreset(experimentalMediaDesignPreset)
        self.experimentalHeroBleedLevel = Self.sanitizedExperimentalHeroBleedLevel(experimentalHeroBleedLevel)
        self.experimentalHomeCardShape = Self.sanitizedExperimentalHomeCardShape(experimentalHomeCardShape)
        self.experimentalMultiGradientPalette = Self.sanitizedExperimentalMultiGradientPalette(experimentalMultiGradientPalette)
        self.experimentalHeroHeightScale = Self.sanitizedExperimentalHeroHeightScale(experimentalHeroHeightScale)
        self.experimentalHeroBleedStrength = Self.sanitizedExperimentalHeroBleedStrength(experimentalHeroBleedStrength)
        self.experimentalHeroFadeDistanceScale = Self.sanitizedExperimentalHeroFadeDistanceScale(experimentalHeroFadeDistanceScale)
        self.experimentalSectionSpacingScale = Self.sanitizedExperimentalSectionSpacingScale(experimentalSectionSpacingScale)
        self.experimentalCardRadiusScale = Self.sanitizedExperimentalCardRadiusScale(experimentalCardRadiusScale)
        self.experimentalMediaCardScale = Self.sanitizedExperimentalMediaCardScale(experimentalMediaCardScale)
        self.experimentalGlassStrength = Self.sanitizedExperimentalGlassStrength(experimentalGlassStrength)
        self.experimentalGradientBaseDarkness = Self.sanitizedExperimentalGradientBaseDarkness(experimentalGradientBaseDarkness)
        self.experimentalGradientAccentIntensity = Self.sanitizedExperimentalGradientAccentIntensity(experimentalGradientAccentIntensity)
        self.experimentalGradientScrollMotion = Self.sanitizedExperimentalGradientScrollMotion(experimentalGradientScrollMotion)
        self.experimentalGradientUseCustomColors = experimentalGradientUseCustomColors
        self.experimentalGradientColorA = experimentalGradientColorA
        self.experimentalGradientColorB = experimentalGradientColorB
        self.experimentalGradientColorC = experimentalGradientColorC
        self.atmosphereStyle = Self.sanitizedAtmosphereStyle(atmosphereStyle)
        self.atmosphereSolidColorSource = Self.sanitizedAtmosphereSolidColorSource(atmosphereSolidColorSource)
        self.atmosphereSolidColor = atmosphereSolidColor
        self.readerAtmosphereStyle = Self.sanitizedAtmosphereStyle(readerAtmosphereStyle)
        self.readerAtmosphereSolidColorSource = Self.sanitizedAtmosphereSolidColorSource(readerAtmosphereSolidColorSource)
        self.readerAtmosphereSolidColor = readerAtmosphereSolidColor
        self.mediaDetailElementOrder = Self.sanitizedMediaDetailElementOrder(mediaDetailElementOrder)
        self.mediaDetailHiddenElements = Self.sanitizedMediaDetailHiddenElements(mediaDetailHiddenElements)
        self.readerDetailElementOrder = Self.sanitizedReaderDetailElementOrder(readerDetailElementOrder)
        self.readerDetailHiddenElements = Self.sanitizedReaderDetailHiddenElements(readerDetailHiddenElements)
        self.mediaColumnsPortrait = mediaColumnsPortrait
        self.mediaColumnsLandscape = mediaColumnsLandscape

        self.readingMode = readingMode
        self.kanzenReaderMode = Self.sanitizedKanzenReaderMode(kanzenReaderMode)
        self.kanzenReaderModeOverrides = Self.sanitizedKanzenReaderModeOverrides(kanzenReaderModeOverrides)
        self.readerDownsampleImages = readerDownsampleImages
        self.readerCropBorders = readerCropBorders
        self.readerDisableQuickActions = readerDisableQuickActions
        self.readerDisableDoubleTap = readerDisableDoubleTap
        self.readerLiveText = readerLiveText
        self.readerHideBarsOnSwipe = readerHideBarsOnSwipe
        self.readerBackgroundColor = Self.sanitizedReaderBackgroundColor(readerBackgroundColor)
        self.readerOrientation = Self.sanitizedReaderOrientation(readerOrientation)
        self.readerTapZones = Self.sanitizedReaderTapZones(readerTapZones)
        self.readerInvertTapZones = readerInvertTapZones
        self.readerAnimatePageTransitions = readerAnimatePageTransitions
        self.readerUpscaleImages = readerUpscaleImages
        self.readerUpscaleMaxHeight = Self.sanitizedReaderUpscaleMaxHeight(readerUpscaleMaxHeight)
        self.readerUpscaleModelName = readerUpscaleModelName
        self.readerPagesToPreload = Self.sanitizedReaderPagesToPreload(readerPagesToPreload)
        self.readerPagedPageLayout = Self.sanitizedReaderPagedPageLayout(readerPagedPageLayout)
        self.readerPagedPageOffset = readerPagedPageOffset
        self.readerPagedPageOffsetOverrides = Self.sanitizedReaderPagedPageOffsetOverrides(readerPagedPageOffsetOverrides)
        self.readerSplitWideImages = readerSplitWideImages
        self.readerReverseSplitOrder = readerReverseSplitOrder
        self.readerVerticalInfiniteScroll = readerVerticalInfiniteScroll
        self.readerPillarbox = readerPillarbox
        self.readerPillarboxAmount = Self.sanitizedReaderPillarboxAmount(readerPillarboxAmount)
        self.readerPillarboxOrientation = Self.sanitizedReaderPillarboxOrientation(readerPillarboxOrientation)
        self.readerOrientationLockEnabled = readerOrientationLockEnabled
        self.readerOrientationLockMask = Self.sanitizedReaderOrientationLockMask(readerOrientationLockMask)
        self.readerReadThresholdPercent = Self.sanitizedReaderReadThresholdPercent(readerReadThresholdPercent)

        self.readerFontSize = Self.sanitizedReaderFontSize(readerFontSize)
        self.readerFontFamily = readerFontFamily
        self.readerFontWeight = readerFontWeight
        self.readerColorPreset = Self.sanitizedReaderColorPreset(readerColorPreset)
        self.readerTextAlignment = readerTextAlignment
        self.readerLineSpacing = Self.sanitizedReaderLineSpacing(readerLineSpacing)
        self.readerMargin = Self.sanitizedReaderMargin(readerMargin)

        self.autoClearCacheEnabled = autoClearCacheEnabled
        self.autoClearCacheThresholdMB = Self.sanitizedAutoClearCacheThresholdMB(autoClearCacheThresholdMB)
        self.highQualityThreshold = Self.sanitizedHighQualityThreshold(highQualityThreshold)
        self.backgroundHLSPipelineEnabled = backgroundHLSPipelineEnabled
        self.readerDownloadsBackgroundEnabled = readerDownloadsBackgroundEnabled
        self.readerDownloadsWifiOnly = readerDownloadsWifiOnly
        self.readerDownloadsParallelLimit = Self.sanitizedReaderDownloadsParallelLimit(readerDownloadsParallelLimit)
        self.autoUpdateServicesEnabled = autoUpdateServicesEnabled
        self.servicesAutoModeEnabled = servicesAutoModeEnabled
        self.servicesAutoSelectEpisodesEnabled = servicesAutoSelectEpisodesEnabled
        self.servicesAutoModeErrorIntelligenceEnabled = servicesAutoModeErrorIntelligenceEnabled
        self.servicesAutoModeSourceIds = Self.sanitizedStringList(servicesAutoModeSourceIds)
        self.servicesAutoModeSourceOrderIds = Self.sanitizedStringList(servicesAutoModeSourceOrderIds)
        self.servicesAutoModeQualityPreference = AutoModeQualityPreference.sanitizedRawValue(servicesAutoModeQualityPreference)
        self.servicesResultMinimumSimilarity = Self.sanitizedServicesResultMinimumSimilarity(servicesResultMinimumSimilarity)
        self.servicesDropMismatchedResults = servicesDropMismatchedResults
        self.servicesStremioStyleSheetEnabled = servicesStremioStyleSheetEnabled
        self.servicesIncludedStreamLanguages = StreamLanguageFilter.sanitizedLanguageList(servicesIncludedStreamLanguages)
        self.servicesHiddenStreamLanguages = StreamLanguageFilter.sanitizedLanguageList(servicesHiddenStreamLanguages)
        self.servicesHideStreamsWithoutLanguageData = servicesHideStreamsWithoutLanguageData
        self.servicesAssumeOriginalAudio = servicesAssumeOriginalAudio
        self.servicesTreatDubbedAnimeAsEnglish = servicesTreatDubbedAnimeAsEnglish
        self.servicesHiddenStreamQualities = StreamLanguageFilter.sanitizedQualityHeights(servicesHiddenStreamQualities)
        self.servicesHideStreamsWithoutDetectedQuality = servicesHideStreamsWithoutDetectedQuality
        self.servicesExtraRulesSourceIds = servicesExtraRulesSourceIds.map(StreamLanguageFilter.sanitizedExtraRulesSourceIds)
        self.githubReleaseAutoCheckEnabled = githubReleaseAutoCheckEnabled
        self.githubReleaseUpdateAvailable = githubReleaseUpdateAvailable
        self.githubReleaseLatestVersion = githubReleaseLatestVersion
        self.githubReleaseURL = githubReleaseURL
        self.githubReleaseShowAlertPending = githubReleaseShowAlertPending
        self.githubReleaseLastPromptedVersion = githubReleaseLastPromptedVersion
        self.filterHorrorContent = filterHorrorContent
        self.selectedSimilarityAlgorithm = Self.sanitizedSimilarityAlgorithm(selectedSimilarityAlgorithm)
        self.performanceModeEnabled = performanceModeEnabled
        self.performanceModeSkipAniListTraversalForAnimeDetails = performanceModeSkipAniListTraversalForAnimeDetails
        self.performanceModeFastAnimeCatalogOverrides = performanceModeFastAnimeCatalogOverrides.filter { PerformanceModeSettings.animeCatalogIds.contains($0.key) }
        self.kanzenHomeSelectedSourceID = kanzenHomeSelectedSourceID
        self.kanzenRecentSourceSearches = Self.sanitizedStringList(kanzenRecentSourceSearches)

        self.collections = Self.sanitizedCollections(collections)
        self.progressData = Self.sanitizedProgressData(progressData)
        self.trackerState = trackerState
        self.catalogs = catalogs
        self.services = services
        self.stremioAddons = stremioAddons
        self.skyStream = skyStream
        self.nuvioPlugins = nuvioPlugins
        self.mangaCollections = mangaCollections
        self.mangaReadingProgress = mangaReadingProgress
        self.mangaCatalogs = mangaCatalogs
        self.customCatalogs = customCatalogs
        self.kanzenModules = kanzenModules
        self.aidokuState = aidokuState.map(Self.aidokuStateWithoutExecutablePayloads)
        self.readerExtensionsState = readerExtensionsState
            ?? self.aidokuState.map(BackupReaderExtensionState.migratingLegacyAidoku)
        self.searchHistory = searchHistory
        self.recommendationCache = Self.sanitizedRecommendationCache(recommendationCache)
        self.userRatings = Self.sanitizedUserRatings(userRatings)
        self.userRatingNotes = Self.sanitizedUserRatingNotes(userRatingNotes)
        self.mediaStateSettings = mediaStateSettings
        self.hasCollections = collectionsPresent
        self.hasProgressData = progressDataPresent
        self.hasTrackerState = trackerStatePresent
        self.hasCatalogs = catalogsPresent
        self.hasServices = servicesPresent
        self.hasMangaCollections = mangaCollectionsPresent
        self.hasMangaReadingProgress = mangaReadingProgressPresent
        self.hasMangaCatalogs = mangaCatalogsPresent
        self.hasCustomCatalogs = customCatalogsPresent
        self.hasKanzenModules = kanzenModulesPresent
        self.hasUserRatings = userRatingsPresent
    }

    private static func decodeUserRatingsIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String: Double]? {
        if let ratings = try? container.decodeIfPresent([String: Double].self, forKey: .userRatings) {
            return sanitizedUserRatings(ratings)
        }

        if let ratings = try? container.decodeIfPresent([String: Int].self, forKey: .userRatings) {
            return sanitizedUserRatings(ratings.mapValues(Double.init))
        }

        return nil
    }

    static func canonicalPositiveTMDBIdentifier(_ rawValue: String) -> String? {
        guard let value = Int(rawValue),
              ProgressPersistencePolicy.validPositiveIdentifier(value),
              rawValue == String(value) else {
            return nil
        }
        return rawValue
    }

    static func sanitizedCollections(_ collections: [BackupCollection]) -> [BackupCollection] {
        collections.map(\.sanitizedForPersistence)
    }

    static func sanitizedRecommendationCache(
        _ results: [TMDBSearchResult]
    ) -> [TMDBSearchResult] {
        Array(results.compactMap(\.sanitizedForPersistence).prefix(10_000))
    }

    static func sanitizedUserRatings(_ ratings: [String: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: ratings.compactMap { key, value -> (String, Double)? in
            guard let identifier = canonicalPositiveTMDBIdentifier(key) else { return nil }
            let finiteValue = value.isFinite ? value : 0.5
            let halfStepValue = (finiteValue * 2).rounded() / 2
            return (identifier, max(0.5, min(10, halfStepValue)))
        })
    }

    static func sanitizedUserRatingNotes(_ notes: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: notes.compactMap { key, value -> (String, String)? in
            guard let identifier = canonicalPositiveTMDBIdentifier(key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return (identifier, trimmed)
        })
    }

    static func sanitizedProgressData(
        _ source: ProgressData,
        preservingDeviceLocalReferences: Bool = false
    ) -> ProgressData {
        ProgressPersistencePolicy.sanitized(
            source,
            preservingDeviceLocalReferences: preservingDeviceLocalReferences
        )
    }

    private static func isPlausibleProgressClock(_ value: Date, now: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite
            && seconds >= 0
            && seconds <= now.timeIntervalSince1970
                + MediaStateEnvelopeValidator.maximumFutureClockSkew
    }

    private static func sanitizedProgressTimes(
        currentTime: Double,
        totalDuration: Double
    ) -> (currentTime: Double, totalDuration: Double)? {
        guard currentTime.isFinite,
              totalDuration.isFinite,
              currentTime >= 0,
              totalDuration >= 0 else {
            return nil
        }
        guard totalDuration > 0 else {
            return currentTime == 0 ? (0, 0) : nil
        }
        return (currentTime, max(totalDuration, currentTime))
    }

    private static func progressEntry<Entry: Encodable>(
        _ candidate: Entry,
        isPreferredOver existing: Entry
    ) -> Bool {
        let candidateDate: Date
        let existingDate: Date
        if let candidate = candidate as? MovieProgressEntry,
           let existing = existing as? MovieProgressEntry {
            candidateDate = candidate.lastUpdated
            existingDate = existing.lastUpdated
        } else if let candidate = candidate as? EpisodeProgressEntry,
                  let existing = existing as? EpisodeProgressEntry {
            candidateDate = candidate.lastUpdated
            existingDate = existing.lastUpdated
        } else {
            return false
        }
        if candidateDate != existingDate { return candidateDate > existingDate }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let candidateData = try? encoder.encode(candidate),
              let existingData = try? encoder.encode(existing) else {
            return false
        }
        return existingData.lexicographicallyPrecedes(candidateData)
    }

    static func sanitizedMPVForegroundFPS(_ value: Int) -> Int {
        value == 60 ? 60 : 30
    }

    static func sanitizedMPVRenderBackend(_: String?) -> String {
        MPVRenderBackend.defaultBackend.rawValue
    }

    static func sanitizedMPVMetalQualityProfile(_ value: String?) -> String {
        guard let value,
              let profile = MPVMetalQualityProfile(rawValue: value) else {
            return MPVMetalQualityProfile.defaultProfile.rawValue
        }
        return profile.rawValue
    }

    static func sanitizedMPVUpscalingMode(_ value: String?) -> String {
        guard let value,
              let mode = MPVUpscalingMode(rawValue: value) else {
            return MPVUpscalingMode.defaultMode.rawValue
        }
        return mode.rawValue
    }

    static func sanitizedMPVNeuralUpscaler(_ value: String?) -> String {
        guard let value,
              let upscaler = MPVNeuralUpscaler(rawValue: value) else {
            return MPVNeuralUpscaler.defaultUpscaler.rawValue
        }
        return upscaler.rawValue
    }

    static func sanitizedMPVPlayerSkin(_ value: String?) -> String {
        if value == "cypberpunk" { return MPVPlayerSkin.cyberpunk.rawValue }
        return MPVPlayerSkin(rawValue: value ?? "")?.rawValue ?? MPVPlayerSkin.defaultSkin.rawValue
    }

    static func sanitizedMediaDetailElementOrder(_ value: String?) -> String {
        MediaDetailElement.rawValue(for: MediaDetailElement.orderedElements(from: value))
    }

    static func sanitizedMediaDetailHiddenElements(_ value: String?) -> String {
        MediaDetailElement.rawValue(for: MediaDetailElement.hiddenElements(from: value, legacyShowCastSection: true))
    }

    static func sanitizedReaderDetailElementOrder(_ value: String?) -> String {
        ReaderDetailElement.rawValue(for: ReaderDetailElement.orderedElements(from: value))
    }

    static func sanitizedReaderDetailHiddenElements(_ value: String?) -> String {
        ReaderDetailElement.rawValue(for: ReaderDetailElement.hiddenElements(from: value))
    }

    static func sanitizedReaderReadThresholdPercent(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 80 }
        return max(50, min(value, 100))
    }

    /// Backup data crosses JSON, property-list, and legacy dictionary
    /// boundaries. Keep every persisted floating-point setting finite before
    /// it can poison an entire JSONEncoder operation, and constrain it to the
    /// same range the live settings UI accepts.
    static func sanitizedFiniteNumericSetting(
        _ value: Double?,
        defaultValue: Double,
        range: ClosedRange<Double>,
        defaultsWhenNonPositive: Bool = false
    ) -> Double {
        guard let value,
              value.isFinite,
              !defaultsWhenNonPositive || value > 0 else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitizedDefaultPlaybackSpeed(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 1,
            range: 0.25...3,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedHoldSpeedPlayer(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 2,
            range: 0.1...3,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedNextEpisodeThreshold(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 0.9,
            range: 0.5...0.99,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedPlayerDoubleTapSeekSeconds(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 10,
            range: 5...60,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedExperimentalFeaturesLastChangedAt(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, Date.distantFuture.timeIntervalSince1970)
    }

    static func sanitizedSubtitleStrokeWidth(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(value, defaultValue: 1, range: 0...10)
    }

    static func sanitizedSubtitleFontSize(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 30,
            range: 8...96,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedSubtitleVerticalOffset(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(value, defaultValue: -6, range: -24...24)
    }

    static func sanitizedReaderFontSize(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 16,
            range: 12...32,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedReaderColorPreset(_ value: Int?) -> Int {
        guard let value, (0...4).contains(value) else { return 0 }
        return value
    }

    static func sanitizedReaderLineSpacing(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 1.6,
            range: 1...3,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedReaderMargin(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(value, defaultValue: 4, range: 0...30)
    }

    static func sanitizedAutoClearCacheThresholdMB(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(
            value,
            defaultValue: 500,
            range: 100...5_000,
            defaultsWhenNonPositive: true
        )
    }

    static func sanitizedHighQualityThreshold(_ value: Double?) -> Double {
        sanitizedFiniteNumericSetting(value, defaultValue: 0.9, range: 0...1)
    }

    private static let maximumLocalNotificationJSONBytes = 262_144
    private static let maximumLocalNotificationSubscriptions = 256
    private static let maximumLocalNotificationReminders = 512
    private static let maximumLocalNotificationNestedValues = 512
    private static let maximumLocalNotificationStringLength = 512
    private static let maximumLocalNotificationTitleLength = 1_024
    private static let maximumLocalNotificationFutureInterval: TimeInterval = 10 * 366 * 24 * 60 * 60

    static func sanitizedLocalNotificationSubscriptions(_ value: String?) -> String? {
        guard let data = boundedLocalNotificationJSONData(value),
              let decoded = try? JSONDecoder().decode(
                [LocalMediaNotificationSubscription].self,
                from: data
              ) else {
            return nil
        }

        let maximumDate = Date().addingTimeInterval(maximumLocalNotificationFutureInterval)
        var seenIDs = Set<String>()
        let sanitized = decoded.compactMap { subscription -> LocalMediaNotificationSubscription? in
            guard seenIDs.count < maximumLocalNotificationSubscriptions,
                  let id = boundedLocalNotificationString(subscription.id),
                  seenIDs.insert(id).inserted,
                  subscription.tmdbID > 0,
                  subscription.tmdbID <= Int(Int32.max),
                  let title = boundedLocalNotificationString(
                    subscription.title,
                    maximumLength: maximumLocalNotificationTitleLength
                  ) else {
                return nil
            }

            let aliases = boundedLocalNotificationStrings(
                subscription.titleAliases + [title],
                maximumCount: 32,
                maximumLength: maximumLocalNotificationTitleLength
            )
            let animeMediaIDs = boundedPositiveLocalNotificationIDs(subscription.animeMediaIDs)
            let animeSpecialMediaIDs = boundedPositiveLocalNotificationIDs(
                subscription.animeSpecialMediaIDs
            ).subtracting(animeMediaIDs)
            let knownWesternSeasonIDs = boundedPositiveLocalNotificationIDs(
                subscription.knownWesternSeasonIDs
            )
            let mutedEpisodeKeys = Set(
                boundedLocalNotificationStrings(
                    Array(subscription.mutedEpisodeKeys),
                    maximumCount: maximumLocalNotificationNestedValues
                )
            )
            var mutedEpisodeExpirations: [String: Date] = [:]
            for (rawKey, expiration) in subscription.mutedEpisodeExpirations
                .sorted(by: { $0.key < $1.key }) {
                guard mutedEpisodeExpirations.count < maximumLocalNotificationNestedValues,
                      let key = boundedLocalNotificationString(rawKey),
                      mutedEpisodeKeys.contains(key),
                      let date = boundedLocalNotificationDate(
                        expiration,
                        maximumDate: maximumDate
                      ) else {
                    continue
                }
                mutedEpisodeExpirations[key] = date
            }

            let seasonPremieres = subscription.seasonPremieres
                .prefix(128)
                .compactMap { premiere -> LocalSeasonPremiere? in
                    guard let premiereID = boundedLocalNotificationString(premiere.id),
                          let premiereTitle = boundedLocalNotificationString(
                            premiere.title,
                            maximumLength: maximumLocalNotificationTitleLength
                          ),
                          let seasonLabel = boundedLocalNotificationString(premiere.seasonLabel) else {
                        return nil
                    }
                    let seasonNumber = premiere.seasonNumber.flatMap {
                        (0...10_000).contains($0) ? $0 : nil
                    }
                    let sourceMediaID = premiere.sourceMediaID.flatMap {
                        $0 > 0 && $0 <= Int(Int32.max) ? $0 : nil
                    }
                    return LocalSeasonPremiere(
                        id: premiereID,
                        title: premiereTitle,
                        seasonLabel: seasonLabel,
                        premiereDate: premiere.premiereDate.flatMap {
                            boundedLocalNotificationDate($0, maximumDate: maximumDate)
                        },
                        hasExactTime: premiere.hasExactTime,
                        seasonNumber: seasonNumber,
                        sourceMediaID: sourceMediaID
                    )
                }

            return LocalMediaNotificationSubscription(
                id: id,
                source: subscription.source,
                tmdbID: subscription.tmdbID,
                title: title,
                titleAliases: aliases.isEmpty ? [title] : aliases,
                animeMediaIDs: animeMediaIDs,
                animeSpecialMediaIDs: animeSpecialMediaIDs,
                knownWesternSeasonIDs: knownWesternSeasonIDs,
                episodeNotifications: subscription.episodeNotifications,
                futureSeasonNotifications: subscription.futureSeasonNotifications,
                mutedEpisodeKeys: mutedEpisodeKeys,
                mutedEpisodeExpirations: mutedEpisodeExpirations,
                seasonPremieres: seasonPremieres,
                hasCompleteAnimeSeasonBaseline: subscription.hasCompleteAnimeSeasonBaseline,
                hasCompleteWesternSeasonBaseline: subscription.hasCompleteWesternSeasonBaseline,
                dateAdded: boundedLocalNotificationDate(
                    subscription.dateAdded,
                    maximumDate: maximumDate
                ) ?? Date(timeIntervalSince1970: 0)
            )
        }
        guard decoded.isEmpty || !sanitized.isEmpty else { return nil }
        return encodedBoundedLocalNotificationJSONString(sanitized)
    }

    static func sanitizedLocalNotificationEpisodeReminders(_ value: String?) -> String? {
        guard let data = boundedLocalNotificationJSONData(value),
              let decoded = try? JSONDecoder().decode(
                [LocalEpisodeNotificationReminder].self,
                from: data
              ) else {
            return nil
        }

        let maximumDate = Date().addingTimeInterval(maximumLocalNotificationFutureInterval)
        var seenIDs = Set<String>()
        let sanitized = decoded.compactMap { reminder -> LocalEpisodeNotificationReminder? in
            guard seenIDs.count < maximumLocalNotificationReminders,
                  let id = boundedLocalNotificationString(reminder.id),
                  seenIDs.insert(id).inserted,
                  reminder.sourceMediaID > 0,
                  reminder.sourceMediaID <= Int(Int32.max),
                  reminder.episode > 0,
                  reminder.episode <= 1_000_000,
                  let title = boundedLocalNotificationString(
                    reminder.title,
                    maximumLength: maximumLocalNotificationTitleLength
                  ),
                  let airingAt = boundedLocalNotificationDate(
                    reminder.airingAt,
                    maximumDate: maximumDate
                  ) else {
                return nil
            }
            let tmdbID = reminder.tmdbID.flatMap {
                $0 > 0 && $0 <= Int(Int32.max) ? $0 : nil
            }
            let season = reminder.season.flatMap {
                (0...10_000).contains($0) ? $0 : nil
            }
            return LocalEpisodeNotificationReminder(
                id: id,
                source: reminder.source,
                sourceMediaID: reminder.sourceMediaID,
                tmdbID: tmdbID,
                tmdbMediaType: tmdbID == nil ? nil : reminder.tmdbMediaType,
                title: title,
                season: season,
                episode: reminder.episode,
                airingAt: airingAt,
                hasKnownAiringTime: reminder.hasKnownAiringTime,
                isStreamingRelease: reminder.isStreamingRelease,
                isAnimeSpecial: reminder.isAnimeSpecial
            )
        }
        guard decoded.isEmpty || !sanitized.isEmpty else { return nil }
        return encodedBoundedLocalNotificationJSONString(sanitized)
    }

    static func sanitizedLocalNotificationEpisodeLeadTime(_ value: Int?) -> Int? {
        value.flatMap(EpisodeNotificationLeadTime.init(rawValue:))?.rawValue
    }

    static func sanitizedLocalNotificationSeasonLeadTime(_ value: Int?) -> Int? {
        value.flatMap(SeasonNotificationLeadTime.init(rawValue:))?.rawValue
    }

    private static func boundedLocalNotificationJSONData(_ value: String?) -> Data? {
        guard let value,
              let data = value.data(using: .utf8),
              data.count <= maximumLocalNotificationJSONBytes else {
            return nil
        }
        return data
    }

    private static func encodedBoundedLocalNotificationJSONString<T: Encodable>(
        _ value: T
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              data.count <= maximumLocalNotificationJSONBytes else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func boundedLocalNotificationString(
        _ value: String,
        maximumLength: Int = maximumLocalNotificationStringLength
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    private static func boundedLocalNotificationStrings(
        _ values: [String],
        maximumCount: Int,
        maximumLength: Int = maximumLocalNotificationStringLength
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard result.count < maximumCount,
                  let bounded = boundedLocalNotificationString(
                    value,
                    maximumLength: maximumLength
                  ),
                  seen.insert(bounded).inserted else {
                continue
            }
            result.append(bounded)
        }
        return result
    }

    private static func boundedPositiveLocalNotificationIDs(_ values: Set<Int>) -> Set<Int> {
        Set(
            values
                .filter { $0 > 0 && $0 <= Int(Int32.max) }
                .sorted()
                .prefix(maximumLocalNotificationNestedValues)
        )
    }

    private static func boundedLocalNotificationDate(
        _ value: Date,
        maximumDate: Date
    ) -> Date? {
        let seconds = value.timeIntervalSince1970
        guard seconds.isFinite,
              seconds >= 0,
              seconds <= maximumDate.timeIntervalSince1970 else {
            return nil
        }
        return value
    }

    static func sanitizedNonEmptyString(_ value: String?, defaultValue: String) -> String {
        guard let value else { return defaultValue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    static func sanitizedAppearance(_ value: String?) -> String {
        guard let value,
              let appearance = Appearance(rawValue: value) else {
            return Appearance.system.rawValue
        }
        return appearance.rawValue
    }

    static func sanitizedHeroBannerBehavior(_ value: String?) -> String {
        guard let value,
              let behavior = HeroBannerBehavior(rawValue: value) else {
            return HeroBannerBehavior.defaultValue.rawValue
        }
        return behavior.rawValue
    }

    static func sanitizedHomeAnimatedBackgroundQuality(_ value: String?) -> String {
        HomeAnimatedBackgroundQuality.resolved(value).rawValue
    }

    static func sanitizedHomeAnimatedBackgroundFrameRate(_ value: String?) -> String {
        HomeAnimatedBackgroundFrameRate.resolved(value).rawValue
    }

    static func sanitizedExperimentalMediaDesignPreset(_ value: String?) -> String {
        guard let value,
              let preset = ExperimentalMediaDesignPreset(rawValue: value) else {
            return ExperimentalMediaDesignPreset.defaultValue.rawValue
        }
        return preset.rawValue
    }

    static func sanitizedExperimentalHeroBleedLevel(_ value: String?) -> String {
        guard let value,
              let level = ExperimentalHeroBleedLevel(rawValue: value) else {
            return ExperimentalHeroBleedLevel.defaultValue.rawValue
        }
        return level.rawValue
    }

    static func sanitizedExperimentalHomeCardShape(_ value: String?) -> String {
        guard let value,
              let shape = ExperimentalHomeCardShape(rawValue: value) else {
            return ExperimentalHomeCardShape.defaultValue.rawValue
        }
        return shape.rawValue
    }

    static func sanitizedExperimentalMultiGradientPalette(_ value: String?) -> String {
        guard let value,
              let palette = ExperimentalMultiGradientPalette(rawValue: value) else {
            return ExperimentalMultiGradientPalette.defaultValue.rawValue
        }
        return palette.rawValue
    }

    static func sanitizedExperimentalHeroHeightScale(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedHeroHeightScale(value)
    }

    static func sanitizedExperimentalHeroBleedStrength(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedHeroBleedStrength(value)
    }

    static func sanitizedExperimentalHeroFadeDistanceScale(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedHeroFadeDistanceScale(value)
    }

    static func sanitizedExperimentalSectionSpacingScale(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedSectionSpacingScale(value)
    }

    static func sanitizedExperimentalCardRadiusScale(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedCardRadiusScale(value)
    }

    static func sanitizedExperimentalMediaCardScale(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedMediaCardScale(value)
    }

    static func sanitizedExperimentalGlassStrength(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedGlassStrength(value)
    }

    static func sanitizedExperimentalGradientBaseDarkness(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedGradientBaseDarkness(value)
    }

    static func sanitizedExperimentalGradientAccentIntensity(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedGradientAccentIntensity(value)
    }

    static func sanitizedExperimentalGradientScrollMotion(_ value: Double?) -> Double {
        ExperimentalVisualTuning.sanitizedGradientScrollMotion(value)
    }

    static func sanitizedAtmosphereStyle(_ value: String?) -> String {
        guard let value,
              let style = AtmosphereStyle(rawValue: value) else {
            return AtmosphereStyle.gradient.rawValue
        }
        return style.rawValue
    }

    static func sanitizedAtmosphereSolidColorSource(_ value: String?) -> String {
        guard let value,
              let source = AtmosphereSolidColorSource(rawValue: value) else {
            return AtmosphereSolidColorSource.dominant.rawValue
        }
        return source.rawValue
    }

    static func defaultKanzenReaderModeRawValue() -> String {
#if !os(tvOS)
        return KanzenReaderMode.currentDefault().rawValue
#else
        return "webtoon"
#endif
    }

    static func sanitizedKanzenReaderMode(_ value: String?) -> String {
#if !os(tvOS)
        guard let value,
              let mode = KanzenReaderMode(rawValue: value) else {
            return defaultKanzenReaderModeRawValue()
        }
        return mode.rawValue
#else
        let allowed = Set(["ltr", "rtl", "webtoon"])
        guard let value, allowed.contains(value) else { return "webtoon" }
        return value
#endif
    }

    static func readingModeRawValue(forKanzenReaderMode value: String) -> Int {
        switch sanitizedKanzenReaderMode(value) {
        case "ltr": return ReadingMode.LTR.rawValue
        case "rtl": return ReadingMode.RTL.rawValue
        case "vertical": return ReadingMode.VERTICAL.rawValue
        default: return ReadingMode.WEBTOON.rawValue
        }
    }

    static func kanzenReaderModeRawValue(forReadingMode value: Int) -> String {
        switch ReadingMode(rawValue: value) ?? .WEBTOON {
        case .LTR: return "ltr"
        case .RTL: return "rtl"
        case .VERTICAL: return "vertical"
        case .WEBTOON: return "webtoon"
        }
    }

    static func sanitizedKanzenReaderModeOverrides(_ values: [String: String]?) -> [String: String] {
        guard let values else { return [:] }
        return values.reduce(into: [String: String]()) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = sanitizedKanzenReaderMode(item.value)
        }
    }

    static func sanitizedReaderOrientation(_ value: String?) -> String {
        guard let value else { return "device" }
        let allowed = Set(["device", "portrait", "landscape", "all"])
        return allowed.contains(value) ? value : "device"
    }

    static func sanitizedReaderTapZones(_ value: String?) -> String {
        guard let value else { return "disabled" }
        let allowed = Set(["auto", "left-right", "l-shaped", "kindle", "edge", "disabled"])
        return allowed.contains(value) ? value : "disabled"
    }

    static func sanitizedReaderUpscaleMaxHeight(_ value: Int?) -> Int {
        guard let value else { return 2000 }
        return max(800, min(value, 6000))
    }

    static func sanitizedReaderPagedPageOffsetOverrides(_ values: [String: Bool]?) -> [String: Bool] {
        guard let values else { return [:] }
        return values.reduce(into: [String: Bool]()) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = item.value
        }
    }

    static func sanitizedReaderBackgroundColor(_ value: String?) -> String {
        guard let value else { return "black" }
        let allowed = Set(["black", "white", "system", "auto"])
        return allowed.contains(value) ? value : "black"
    }

    static func sanitizedReaderPagesToPreload(_ value: Int?) -> Int {
        guard let value else { return 3 }
        return max(1, min(value, 10))
    }

    static func sanitizedReaderPagedPageLayout(_ value: String?) -> String {
        guard let value else { return "single" }
        let allowed = Set(["single", "double", "auto"])
        return allowed.contains(value) ? value : "single"
    }

    static func sanitizedReaderPillarboxAmount(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 15 }
        return max(5, min(value, 95))
    }

    static func sanitizedReaderPillarboxOrientation(_ value: String?) -> String {
        guard let value else { return "both" }
        let allowed = Set(["both", "portrait", "landscape"])
        return allowed.contains(value) ? value : "both"
    }

    static func sanitizedReaderOrientationLockMask(_ value: String?) -> String {
        guard let value else { return "all" }
        let allowed = Set(["portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight", "landscape", "all"])
        return allowed.contains(value) ? value : "all"
    }

    static func sanitizedReaderDownloadsParallelLimit(_ value: Int?) -> Int {
        guard let value else { return 2 }
        return max(1, min(value, 4))
    }

    static func sanitizedStringList(_ values: [String]?) -> [String] {
        var result: [String] = []
        for value in values ?? [] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }

    static func sanitizedSimilarityAlgorithm(_ value: String?) -> String {
        guard let value,
              let algorithm = SimilarityAlgorithm(rawValue: value) else {
            return SimilarityAlgorithm.hybrid.rawValue
        }
        return algorithm.rawValue
    }

    static func sanitizedServicesResultMinimumSimilarity(_ value: Double?) -> Double {
        ServicesResultRankingSettings.clampedMinimumSimilarity(
            value ?? ServicesResultRankingSettings.defaultMinimumSimilarity
        )
    }

    static func optionalInt(from value: Any?, defaultValue: Int) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double,
           double.isFinite,
           let exact = Int(exactly: double) {
            return exact
        }
        return defaultValue
    }

    static func optionalDouble(from value: Any?, defaultValue: Double) -> Double {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        return defaultValue.isFinite ? defaultValue : 0
    }

    static func stringList(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    static func intList(from value: Any?) -> [Int] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { value in
            if let intValue = value as? Int { return intValue }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
            return nil
        }
    }

}

extension BackupData: @unchecked Sendable {}

struct BackupService: Codable, Equatable {
    let id: UUID
    let url: String
    let jsonMetadata: String
    let jsScript: String
    let isActive: Bool
    let sortIndex: Int64
}

struct BackupStremioAddon: Codable, Equatable {
    let id: UUID
    let configuredURL: String
    let manifestJSON: String
    let isActive: Bool
    let sortIndex: Int64

    init(id: UUID, configuredURL: String, manifestJSON: String, isActive: Bool, sortIndex: Int64) {
        self.id = id
        self.configuredURL = configuredURL
        self.manifestJSON = manifestJSON
        self.isActive = isActive
        self.sortIndex = sortIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        configuredURL = try container.decodeIfPresent(String.self, forKey: .configuredURL) ?? ""
        manifestJSON = try container.decodeIfPresent(String.self, forKey: .manifestJSON) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sortIndex = try container.decodeIfPresent(Int64.self, forKey: .sortIndex) ?? 0
    }
}

struct ExperimentalCloudNuvioRestorePlan: Equatable {
    let state: NuvioStoredPluginsState
    let deviceLocalSourceIDs: Set<String>
}

enum ExperimentalCloudLocalSourceSelectionPolicy {
    static func membership(
        current: [String],
        incoming: [String],
        preserving deviceLocalSourceIDs: Set<String>
    ) -> [String] {
        let sanitizedCurrent = BackupData.sanitizedStringList(current)
        var seen = Set<String>()
        var result = BackupData.sanitizedStringList(incoming).filter {
            !deviceLocalSourceIDs.contains($0) && seen.insert($0).inserted
        }
        result.append(contentsOf: sanitizedCurrent.filter {
            deviceLocalSourceIDs.contains($0) && seen.insert($0).inserted
        })
        return BackupData.sanitizedStringList(result)
    }

    static func order(
        current: [String],
        incoming: [String],
        preserving deviceLocalSourceIDs: Set<String>
    ) -> [String] {
        let sanitizedCurrent = BackupData.sanitizedStringList(current)
        let restoredShared = BackupData.sanitizedStringList(incoming).filter {
            !deviceLocalSourceIDs.contains($0)
        }
        var sharedIterator = restoredShared.makeIterator()
        var result: [String] = []
        var seen = Set<String>()

        // Preserve the receiver-only entries in their existing slots while
        // allowing the accepted cloud order to replace every shared slot.
        for currentID in sanitizedCurrent {
            let next = deviceLocalSourceIDs.contains(currentID)
                ? currentID
                : sharedIterator.next()
            if let next, seen.insert(next).inserted { result.append(next) }
        }
        while let next = sharedIterator.next() {
            if seen.insert(next).inserted { result.append(next) }
        }
        for localID in sanitizedCurrent where deviceLocalSourceIDs.contains(localID) {
            if seen.insert(localID).inserted { result.append(localID) }
        }
        return BackupData.sanitizedStringList(result)
    }

    static func restoredValue(
        _ incoming: Any,
        forKey key: String,
        currentStore: UserDefaults,
        preserving deviceLocalSourceIDs: Set<String>
    ) -> Any {
        guard !deviceLocalSourceIDs.isEmpty,
              let incomingValues = incoming as? [String] else { return incoming }
        let currentValues = currentStore.stringArray(forKey: key) ?? []
        switch key {
        case "servicesAutoModeSourceIds", "servicesExtraRulesSourceIds":
            return membership(
                current: currentValues,
                incoming: incomingValues,
                preserving: deviceLocalSourceIDs
            )
        case "servicesAutoModeSourceOrderIds":
            return order(
                current: currentValues,
                incoming: incomingValues,
                preserving: deviceLocalSourceIDs
            )
        default:
            return incoming
        }
    }
}

enum ExperimentalCloudSourceRestorePolicy {
    static func services(
        current: [BackupService],
        incoming: [BackupService]
    ) -> [BackupService] {
        let deviceLocal = current.filter {
            BackupData.serviceForExperimentalCloudSync($0) == nil
        }
        let deviceLocalIDs = Set(deviceLocal.map(\.id))
        return (incoming.filter { !deviceLocalIDs.contains($0.id) } + deviceLocal).sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.id.uuidString < $1.id.uuidString
                : $0.sortIndex < $1.sortIndex
        }
    }

    static func stremioAddons(
        current: [BackupStremioAddon],
        incoming: [BackupStremioAddon]
    ) -> [BackupStremioAddon] {
        let deviceLocal = current.filter {
            BackupData.stremioAddonForExperimentalCloudSync($0) == nil
        }
        let deviceLocalIDs = Set(deviceLocal.map(\.id))
        return (incoming.filter { !deviceLocalIDs.contains($0.id) } + deviceLocal).sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.id.uuidString < $1.id.uuidString
                : $0.sortIndex < $1.sortIndex
        }
    }
}

struct BackupMangaCollection: Codable {
    let id: UUID
    let name: String
    let items: [MangaLibraryItem]
    let description: String?
}

struct BackupKanzenModule: Codable {
    let id: UUID
    let moduleData: ModuleData
    let localPath: String
    let moduleurl: String
    let isActive: Bool
}

struct BackupAidokuSourceListRecord: Codable {
    let url: String
    let name: String
    let sourceCount: Int
    let lastRefresh: Date?
    let lastError: String?
}

private enum BackupAidokuLegacyWirePolicy {
    static let maximumInstalledSources = 512
    static let maximumSourceLists = 100
    static let maximumLanguages = 128
    static let maximumSourceIDBytes = 192
    static let maximumNameBytes = 512
    static let maximumLanguageBytes = 32
    static let maximumPathBytes = 4 * 1_024
    static let maximumURLBytes = 16 * 1_024
    static let maximumErrorBytes = 4 * 1_024

    private static let sourceIDCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: ".-_")
    )
    private static let languageCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-_")
    )

    static func sourceID(_ rawValue: String, codingPath: [CodingKey]) throws -> String {
        let value = rawValue.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumSourceIDBytes,
              value.unicodeScalars.allSatisfy(sourceIDCharacters.contains) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Legacy Reader source identity is invalid."
            ))
        }
        return value
    }

    static func requiredString(
        _ rawValue: String,
        maximumBytes: Int,
        field: String,
        codingPath: [CodingKey]
    ) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Legacy Reader source \(field) is invalid."
            ))
        }
        return value
    }

    static func optionalString(
        _ rawValue: String?,
        maximumBytes: Int,
        field: String,
        codingPath: [CodingKey]
    ) throws -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Legacy Reader source \(field) is invalid."
            ))
        }
        return value
    }

    static func language(_ rawValue: String, codingPath: [CodingKey]) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.utf8.count <= maximumLanguageBytes,
              value.unicodeScalars.allSatisfy(languageCharacters.contains) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Legacy Reader source language is invalid."
            ))
        }
        return value
    }

    static func isSafeDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (-62_135_596_800...253_402_300_799).contains(seconds)
    }

    static func isSafeDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

private struct BackupAidokuBoundedLanguages: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count, count > BackupAidokuLegacyWirePolicy.maximumLanguages {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Legacy Reader source language list is too large."
            )
        }
        var result: [String] = []
        var seen = Set<String>()
        var decodedCount = 0
        while !container.isAtEnd {
            guard decodedCount < BackupAidokuLegacyWirePolicy.maximumLanguages else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Legacy Reader source language list is too large."
                )
            }
            decodedCount += 1
            let value = try BackupAidokuLegacyWirePolicy.language(
                container.decode(String.self),
                codingPath: container.codingPath
            )
            if seen.insert(value).inserted { result.append(value) }
        }
        values = result.sorted()
    }
}

struct BackupAidokuInstalledSource: Codable {
    let id: String
    let name: String
    let version: Int
    let languages: [String]
    let iconPath: String?
    let externalIconURL: String?
    let contentRatingRawValue: Int
    let sourceListURL: String?
    let packageURL: String?
    let isEnabled: Bool
    let order: Int
    let lastUpdated: Date?
    let lastError: String?

    var packageDigest: String? = nil
    let payloadArchiveData: Data?
}

extension BackupAidokuInstalledSource {
    private enum CodingKeys: String, CodingKey {
        case id, name, version, languages, iconPath, externalIconURL
        case contentRatingRawValue, sourceListURL, packageURL, isEnabled, order
        case lastUpdated, lastError, packageDigest, payloadArchiveData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try BackupAidokuLegacyWirePolicy.sourceID(
            container.decode(String.self, forKey: .id),
            codingPath: container.codingPath + [CodingKeys.id]
        )
        name = try BackupAidokuLegacyWirePolicy.requiredString(
            container.decode(String.self, forKey: .name),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumNameBytes,
            field: "name",
            codingPath: container.codingPath + [CodingKeys.name]
        )

        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard (0...Int(Int32.max)).contains(decodedVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Legacy Reader source version is invalid."
            )
        }
        version = decodedVersion
        languages = try container.decode(
            BackupAidokuBoundedLanguages.self,
            forKey: .languages
        ).values
        iconPath = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .iconPath),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumPathBytes,
            field: "icon path",
            codingPath: container.codingPath + [CodingKeys.iconPath]
        )
        externalIconURL = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .externalIconURL),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
            field: "external icon URL",
            codingPath: container.codingPath + [CodingKeys.externalIconURL]
        )

        let decodedRating = try container.decode(Int.self, forKey: .contentRatingRawValue)
        guard (0...3).contains(decodedRating) else {
            throw DecodingError.dataCorruptedError(
                forKey: .contentRatingRawValue,
                in: container,
                debugDescription: "Legacy Reader source content rating is invalid."
            )
        }
        contentRatingRawValue = decodedRating
        sourceListURL = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .sourceListURL),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
            field: "source-list URL",
            codingPath: container.codingPath + [CodingKeys.sourceListURL]
        )
        packageURL = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .packageURL),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
            field: "package URL",
            codingPath: container.codingPath + [CodingKeys.packageURL]
        )
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)

        let decodedOrder = try container.decode(Int.self, forKey: .order)
        guard (0...10_000).contains(decodedOrder) else {
            throw DecodingError.dataCorruptedError(
                forKey: .order,
                in: container,
                debugDescription: "Legacy Reader source order is invalid."
            )
        }
        order = decodedOrder

        let decodedDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        guard decodedDate.map(BackupAidokuLegacyWirePolicy.isSafeDate) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastUpdated,
                in: container,
                debugDescription: "Legacy Reader source update date is invalid."
            )
        }
        lastUpdated = decodedDate
        lastError = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .lastError),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumErrorBytes,
            field: "error",
            codingPath: container.codingPath + [CodingKeys.lastError]
        )
        if let decodedDigest = try container.decodeIfPresent(String.self, forKey: .packageDigest) {
            guard BackupAidokuLegacyWirePolicy.isSafeDigest(decodedDigest) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .packageDigest,
                    in: container,
                    debugDescription: "Legacy Reader source package digest is invalid."
                )
            }
            packageDigest = decodedDigest.lowercased()
        } else {
            packageDigest = nil
        }

        // Executable legacy archives are intentionally never materialized from a
        // backup. The key remains decode-recognized solely for old wire input.
        payloadArchiveData = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(languages, forKey: .languages)
        try container.encodeIfPresent(iconPath, forKey: .iconPath)
        try container.encodeIfPresent(externalIconURL, forKey: .externalIconURL)
        try container.encode(contentRatingRawValue, forKey: .contentRatingRawValue)
        try container.encodeIfPresent(sourceListURL, forKey: .sourceListURL)
        try container.encodeIfPresent(packageURL, forKey: .packageURL)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(packageDigest, forKey: .packageDigest)
        // Never write executable provider archive bytes into a new backup.
    }
}

private struct BackupAidokuBoundedInstalledSources: Decodable {
    let values: [BackupAidokuInstalledSource]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count, count > BackupAidokuLegacyWirePolicy.maximumInstalledSources {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Legacy Reader installed-source list is too large."
            )
        }
        var result: [BackupAidokuInstalledSource] = []
        var seen = Set<String>()
        while !container.isAtEnd {
            guard result.count < BackupAidokuLegacyWirePolicy.maximumInstalledSources else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Legacy Reader installed-source list is too large."
                )
            }
            let source = try container.decode(BackupAidokuInstalledSource.self)
            guard seen.insert(source.id).inserted else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Legacy Reader installed-source identities must be unique."
                )
            }
            result.append(source)
        }
        values = result
    }
}

private struct BackupAidokuDecodedSourceListRecord: Decodable {
    let value: BackupAidokuSourceListRecord

    private enum CodingKeys: String, CodingKey {
        case url, name, sourceCount, lastRefresh, lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try BackupAidokuLegacyWirePolicy.requiredString(
            container.decode(String.self, forKey: .url),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
            field: "source-list URL",
            codingPath: container.codingPath + [CodingKeys.url]
        )
        let name = try BackupAidokuLegacyWirePolicy.requiredString(
            container.decode(String.self, forKey: .name),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumNameBytes,
            field: "source-list name",
            codingPath: container.codingPath + [CodingKeys.name]
        )
        let sourceCount = try container.decode(Int.self, forKey: .sourceCount)
        guard (0...Int(Int32.max)).contains(sourceCount) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceCount,
                in: container,
                debugDescription: "Legacy Reader source-list count is invalid."
            )
        }
        let lastRefresh = try container.decodeIfPresent(Date.self, forKey: .lastRefresh)
        guard lastRefresh.map(BackupAidokuLegacyWirePolicy.isSafeDate) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastRefresh,
                in: container,
                debugDescription: "Legacy Reader source-list refresh date is invalid."
            )
        }
        let lastError = try BackupAidokuLegacyWirePolicy.optionalString(
            container.decodeIfPresent(String.self, forKey: .lastError),
            maximumBytes: BackupAidokuLegacyWirePolicy.maximumErrorBytes,
            field: "source-list error",
            codingPath: container.codingPath + [CodingKeys.lastError]
        )
        value = BackupAidokuSourceListRecord(
            url: url,
            name: name,
            sourceCount: sourceCount,
            lastRefresh: lastRefresh,
            lastError: lastError
        )
    }
}

private struct BackupAidokuBoundedSourceLists: Decodable {
    let values: [BackupAidokuSourceListRecord]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count, count > BackupAidokuLegacyWirePolicy.maximumSourceLists {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Legacy Reader source-list metadata is too large."
            )
        }
        var result: [BackupAidokuSourceListRecord] = []
        while !container.isAtEnd {
            guard result.count < BackupAidokuLegacyWirePolicy.maximumSourceLists else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Legacy Reader source-list metadata is too large."
                )
            }
            result.append(try container.decode(BackupAidokuDecodedSourceListRecord.self).value)
        }
        values = result
    }
}

struct BackupSkyStreamSharedPayload: Codable {
    let packageID: String

    let payloadRelativePath: String
    let scriptSHA256: String
    let archiveSHA256: String
    let script: Data
    let archive: Data?
}

struct BackupNuvioSharedPayload: Codable {
    let repositoryID: String

    let scraperID: String
    let codeFileName: String
    let code: String
}

struct NuvioSharedPayloadMigrationResult {
    var backup: BackupData
    var migratedPayloadCount: Int
    var refusedPayloadCount: Int
}

struct BackupAidokuState: Codable {
    var sourceLists: [BackupAidokuSourceListRecord] = []
    var installedSources: [BackupAidokuInstalledSource] = []
    var showMatureSources: Bool = false
    var autoUpdateSources: Bool = true
    var lastAutoUpdate: Date?

    var sharedPayloads: [String: Data]? = nil
}

extension BackupAidokuState {
    private enum CodingKeys: String, CodingKey {
        case sourceLists, installedSources, showMatureSources, autoUpdateSources
        case lastAutoUpdate, sharedPayloads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLists = try container.decodeIfPresent(
            BackupAidokuBoundedSourceLists.self,
            forKey: .sourceLists
        )?.values ?? []
        installedSources = try container.decodeIfPresent(
            BackupAidokuBoundedInstalledSources.self,
            forKey: .installedSources
        )?.values ?? []
        showMatureSources = try container.decodeIfPresent(Bool.self, forKey: .showMatureSources) ?? false
        autoUpdateSources = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateSources) ?? true
        let decodedDate = try container.decodeIfPresent(Date.self, forKey: .lastAutoUpdate)
        guard decodedDate.map(BackupAidokuLegacyWirePolicy.isSafeDate) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastAutoUpdate,
                in: container,
                debugDescription: "Legacy Reader auto-update date is invalid."
            )
        }
        lastAutoUpdate = decodedDate

        // Old shared archives contain executable provider packages. Do not ask
        // Decoder to materialize their keys or base64 bodies at ingress.
        sharedPayloads = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceLists, forKey: .sourceLists)
        try container.encode(installedSources, forKey: .installedSources)
        try container.encode(showMatureSources, forKey: .showMatureSources)
        try container.encode(autoUpdateSources, forKey: .autoUpdateSources)
        try container.encodeIfPresent(lastAutoUpdate, forKey: .lastAutoUpdate)
        // Never write executable shared provider archives into a new backup.
    }
}

/// Inert metadata retained for reconnecting library entries that were backed by Aidoku.
/// Source-list/package URLs and executable bytes are deliberately not carried forward.
struct BackupLegacyAidokuSourceMetadata: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: Int
    let languages: [String]
    let originHost: String?
    let contentRatingRawValue: Int
    let isEnabled: Bool
    let order: Int
    let lastUpdated: Date?

    private enum CodingKeys: String, CodingKey {
        case id, name, version, languages, originHost, contentRatingRawValue
        case isEnabled, order, lastUpdated
    }

    fileprivate init?(_ source: BackupAidokuInstalledSource) {
        let canonicalID = source.id.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedIDCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-_")
        )
        guard !canonicalID.isEmpty,
              canonicalID.utf8.count <= 192,
              canonicalID.unicodeScalars.allSatisfy(allowedIDCharacters.contains) else {
            return nil
        }

        id = canonicalID
        name = Self.boundedString(source.name, maximumUTF8Bytes: 512) ?? canonicalID
        version = Swift.min(Swift.max(0, source.version), Int(Int32.max))
        languages = Array(
            Set(
                source.languages.compactMap {
                    Self.boundedString(
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        maximumUTF8Bytes: 32
                    )
                }
            )
        ).sorted().prefix(BackupAidokuLegacyWirePolicy.maximumLanguages).map { $0 }
        originHost = Self.safeOriginHost(source.packageURL)
        contentRatingRawValue = min(max(source.contentRatingRawValue, 0), 3)
        isEnabled = source.isEnabled
        order = min(max(source.order, 0), 10_000)
        lastUpdated = source.lastUpdated.flatMap { Self.isSafeDate($0) ? $0 : nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedID = try container.decode(String.self, forKey: .id)
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedIDCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-_")
        )
        guard !decodedID.isEmpty,
              decodedID.utf8.count <= 192,
              decodedID.unicodeScalars.allSatisfy(allowedIDCharacters.contains) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Legacy Reader source identity is invalid."
            )
        }
        id = decodedID

        let decodedName = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedName.isEmpty,
              decodedName.utf8.count <= 512,
              !decodedName.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Legacy Reader source name is invalid."
            )
        }
        name = decodedName

        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard (0...Int(Int32.max)).contains(decodedVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Legacy Reader source version is invalid."
            )
        }
        version = decodedVersion

        var languageContainer = try container.nestedUnkeyedContainer(forKey: .languages)
        if let count = languageContainer.count,
           count > BackupAidokuLegacyWirePolicy.maximumLanguages {
            throw DecodingError.dataCorruptedError(
                forKey: .languages,
                in: container,
                debugDescription: "Legacy Reader source language list is too large."
            )
        }
        var decodedLanguages: [String] = []
        var seenLanguages = Set<String>()
        let allowedLanguageCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        while !languageContainer.isAtEnd {
            guard decodedLanguages.count < BackupAidokuLegacyWirePolicy.maximumLanguages else {
                throw DecodingError.dataCorruptedError(
                    forKey: .languages,
                    in: container,
                    debugDescription: "Legacy Reader source language list is too large."
                )
            }
            let language = try languageContainer.decode(String.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !language.isEmpty,
                  language.utf8.count <= 32,
                  language.unicodeScalars.allSatisfy(allowedLanguageCharacters.contains) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .languages,
                    in: container,
                    debugDescription: "Legacy Reader source language is invalid."
                )
            }
            if seenLanguages.insert(language).inserted {
                decodedLanguages.append(language)
            }
        }
        languages = decodedLanguages.sorted()

        if let decodedHost = try container.decodeIfPresent(String.self, forKey: .originHost) {
            guard let safeHost = Self.safeStoredOriginHost(decodedHost) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .originHost,
                    in: container,
                    debugDescription: "Legacy Reader source origin host is invalid."
                )
            }
            originHost = safeHost
        } else {
            originHost = nil
        }

        let decodedRating = try container.decode(Int.self, forKey: .contentRatingRawValue)
        guard (0...3).contains(decodedRating) else {
            throw DecodingError.dataCorruptedError(
                forKey: .contentRatingRawValue,
                in: container,
                debugDescription: "Legacy Reader source content rating is invalid."
            )
        }
        contentRatingRawValue = decodedRating
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)

        let decodedOrder = try container.decode(Int.self, forKey: .order)
        guard (0...10_000).contains(decodedOrder) else {
            throw DecodingError.dataCorruptedError(
                forKey: .order,
                in: container,
                debugDescription: "Legacy Reader source order is invalid."
            )
        }
        order = decodedOrder

        let decodedDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        guard decodedDate.map(Self.isSafeDate) ?? true else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastUpdated,
                in: container,
                debugDescription: "Legacy Reader source update date is invalid."
            )
        }
        lastUpdated = decodedDate
    }

    var legacyStableKeyPrefix: String {
        "aidoku:\(id):"
    }

    private static func safeOriginHost(_ rawValue: String?) -> String? {
        guard let rawValue,
              rawValue.utf8.count <= 4_096,
              let components = URLComponents(string: rawValue),
              components.user == nil,
              components.password == nil,
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host.utf8.count <= 253 else { return nil }
        return host
    }

    private static func safeStoredOriginHost(_ rawValue: String) -> String? {
        var candidate = rawValue.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while candidate.hasSuffix(".") { candidate.removeLast() }
        guard !candidate.isEmpty,
              candidate.utf8.count <= 253,
              !candidate.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }),
              !candidate.contains("/"),
              !candidate.contains("?"),
              !candidate.contains("#"),
              !candidate.contains("@") else {
            return nil
        }
        let authority = candidate.contains(":") ? "[\(candidate)]" : candidate
        guard let components = URLComponents(string: "https://\(authority)"),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              components.host?.lowercased() == candidate else {
            return nil
        }
        return candidate
    }

    private static func isSafeDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (-62_135_596_800...253_402_300_799).contains(seconds)
    }

    private static func boundedString(_ value: String, maximumUTF8Bytes: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        if trimmed.utf8.count <= maximumUTF8Bytes { return trimmed }
        var result = ""
        for character in trimmed {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumUTF8Bytes else { break }
            result = candidate
        }
        return result.isEmpty ? nil : result
    }
}

/// The portable Reader Extensions backup envelope. `metadataJSON` is a bounded encoding of
/// `ReaderExtensionBackupSnapshot`; its validation rejects executable, authentication, domain
/// approval, local-file, and content-digest fields before it can enter a backup or cloud state.
struct BackupReaderExtensionState: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maximumMetadataBytes = 2 * 1_024 * 1_024
    static let maximumInstalledSources = 1_000
    static let maximumRepositories = 100
    static let maximumLegacySources = 512

    var schemaVersion: Int = currentSchemaVersion
    var metadataJSON: Data?
    var installedSourceCount: Int
    var legacyAidokuSources: [BackupLegacyAidokuSourceMetadata]
    var showMatureSources: Bool
    var autoUpdateSources: Bool
    var lastAutoUpdate: Date?

    init(
        metadataJSON: Data?,
        installedSourceCount: Int,
        legacyAidokuSources: [BackupLegacyAidokuSourceMetadata] = [],
        showMatureSources: Bool,
        autoUpdateSources: Bool,
        lastAutoUpdate: Date?
    ) {
        self.metadataJSON = Self.sanitizedMetadataJSON(metadataJSON)
        self.installedSourceCount = min(max(installedSourceCount, 0), Self.maximumInstalledSources)
        self.legacyAidokuSources = Self.sanitizedLegacySources(legacyAidokuSources)
        self.showMatureSources = showMatureSources
        self.autoUpdateSources = autoUpdateSources
        self.lastAutoUpdate = lastAutoUpdate
    }

    var sourceCountForCompatibility: Int {
        min(
            Self.maximumInstalledSources,
            installedSourceCount + legacyAidokuSources.count
        )
    }

    static func migratingLegacyAidoku(_ incoming: BackupAidokuState) -> Self {
        let metadata = sanitizedLegacySources(
            incoming.installedSources.compactMap(BackupLegacyAidokuSourceMetadata.init)
        )
        return Self(
            metadataJSON: nil,
            installedSourceCount: 0,
            legacyAidokuSources: metadata,
            showMatureSources: incoming.showMatureSources,
            autoUpdateSources: incoming.autoUpdateSources,
            lastAutoUpdate: incoming.lastAutoUpdate
        )
    }

    func sanitized() -> Self {
        Self(
            metadataJSON: metadataJSON,
            installedSourceCount: installedSourceCount,
            legacyAidokuSources: legacyAidokuSources,
            showMatureSources: showMatureSources,
            autoUpdateSources: autoUpdateSources,
            lastAutoUpdate: lastAutoUpdate
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, metadataJSON, installedSourceCount, legacyAidokuSources
        case showMatureSources, autoUpdateSources, lastAutoUpdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchema = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        schemaVersion = Self.currentSchemaVersion
        metadataJSON = decodedSchema == Self.currentSchemaVersion
            ? Self.sanitizedMetadataJSON(
                try container.decodeIfPresent(Data.self, forKey: .metadataJSON)
            )
            : nil
        installedSourceCount = min(
            max(try container.decodeIfPresent(Int.self, forKey: .installedSourceCount) ?? 0, 0),
            Self.maximumInstalledSources
        )
        let decodedLegacySources = try container.decodeIfPresent(
            BoundedLegacySources.self,
            forKey: .legacyAidokuSources
        )?.values ?? []
        let sanitizedLegacySources = Self.sanitizedLegacySources(decodedLegacySources)
        guard decodedLegacySources.count <= Self.maximumLegacySources,
              sanitizedLegacySources.count == decodedLegacySources.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .legacyAidokuSources,
                in: container,
                debugDescription: "Legacy Reader source metadata is invalid or too large."
            )
        }
        legacyAidokuSources = sanitizedLegacySources
        showMatureSources = try container.decodeIfPresent(Bool.self, forKey: .showMatureSources) ?? false
        autoUpdateSources = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateSources) ?? true
        lastAutoUpdate = try container.decodeIfPresent(Date.self, forKey: .lastAutoUpdate)
    }

    func encode(to encoder: Encoder) throws {
        let state = sanitized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(state.metadataJSON, forKey: .metadataJSON)
        try container.encode(state.installedSourceCount, forKey: .installedSourceCount)
        try container.encode(state.legacyAidokuSources, forKey: .legacyAidokuSources)
        try container.encode(state.showMatureSources, forKey: .showMatureSources)
        try container.encode(state.autoUpdateSources, forKey: .autoUpdateSources)
        try container.encodeIfPresent(state.lastAutoUpdate, forKey: .lastAutoUpdate)
    }

    fileprivate static func sanitizedMetadataJSON(_ data: Data?) -> Data? {
        guard let data,
              !data.isEmpty,
              data.count <= maximumMetadataBytes,
              (try? ReaderExtensionJSONPreflight.validate(data, limits: .init(
                  maximumBytes: maximumMetadataBytes,
                  maximumDepth: 18,
                  maximumContainerEntries: maximumInstalledSources,
                  maximumTopLevelEntries: 5,
                  maximumTotalTokens: 256_000,
                  // Decoded metadata strings are capped at 32 KiB below;
                  // allow the bounded expansion introduced by JSON escaping.
                  maximumStringBytes: 64 * 1_024
              ))) != nil,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys).isSubset(of: [
                  "repositories",
                  "installedSources",
                  "showMatureSources",
                  "autoUpdateSources",
                  "lastAutoUpdate"
              ]),
              (dictionary["repositories"] as? [Any])?.count ?? 0 <= maximumRepositories,
              (dictionary["installedSources"] as? [Any])?.count ?? 0 <= maximumInstalledSources,
              metadataObjectIsSafe(dictionary, depth: 0),
              JSONSerialization.isValidJSONObject(dictionary),
              let canonical = try? JSONSerialization.data(
                  withJSONObject: dictionary,
                  options: [.sortedKeys]
              ),
              canonical.count <= maximumMetadataBytes else {
            return nil
        }
        return canonical
    }

    private static func metadataObjectIsSafe(_ value: Any, depth: Int) -> Bool {
        guard depth <= 16 else { return false }
        if let dictionary = value as? [String: Any] {
            guard dictionary.count <= 256 else { return false }
            for (key, nestedValue) in dictionary {
                guard key.utf8.count <= 128,
                      !isForbiddenMetadataKey(key),
                      sensitiveMetadataFieldIsEmpty(key: key, value: nestedValue),
                      metadataObjectIsSafe(nestedValue, depth: depth + 1) else {
                    return false
                }
            }
            return true
        }
        if let array = value as? [Any] {
            return array.count <= maximumInstalledSources
                && array.allSatisfy { metadataObjectIsSafe($0, depth: depth + 1) }
        }
        if let string = value as? String {
            return string.utf8.count <= 32 * 1_024
        }
        return value is NSNumber || value is NSNull
    }

    private static func isForbiddenMetadataKey(_ key: String) -> Bool {
        switch key.lowercased().replacingOccurrences(of: "_", with: "") {
        case "script", "sourcecode", "code", "payload", "archive", "archivepayload",
             "cookie", "cookies", "secret", "secrets", "authorization", "headers",
             "approveddomains", "approvedhosts", "localfilename", "localpath",
             "contentdigest", "scriptdigest", "packagesha256", "payloadsha256":
            return true
        default:
            return false
        }
    }

    private static func sensitiveMetadataFieldIsEmpty(key: String, value: Any) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
        if normalized.hasSuffix("contentdigest") || normalized == "declareddomains" {
            if value is NSNull { return true }
            if let array = value as? [Any] { return array.isEmpty }
            return false
        }
        return true
    }

    fileprivate static func sanitizedLegacySources(
        _ sources: [BackupLegacyAidokuSourceMetadata]
    ) -> [BackupLegacyAidokuSourceMetadata] {
        var seen = Set<String>()
        return sources.sorted {
            if $0.order == $1.order { return $0.id < $1.id }
            return $0.order < $1.order
        }.filter {
            seen.insert($0.id).inserted
        }.prefix(maximumLegacySources).map { $0 }
    }

    fileprivate static func decodeLegacySources(
        from data: Data
    ) throws -> [BackupLegacyAidokuSourceMetadata] {
        guard !data.isEmpty, data.count <= maximumMetadataBytes else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Legacy Reader source metadata is too large.")
            )
        }
        let decoded = try JSONDecoder().decode(BoundedLegacySources.self, from: data).values
        let sanitized = sanitizedLegacySources(decoded)
        guard sanitized.count == decoded.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Legacy Reader source metadata contains duplicate identities.")
            )
        }
        return sanitized
    }

    private struct BoundedLegacySources: Decodable {
        let values: [BackupLegacyAidokuSourceMetadata]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            if let count = container.count, count > BackupReaderExtensionState.maximumLegacySources {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Legacy Reader source metadata is too large."
                )
            }
            var decoded: [BackupLegacyAidokuSourceMetadata] = []
            decoded.reserveCapacity(
                Swift.min(
                    container.count ?? 0,
                    BackupReaderExtensionState.maximumLegacySources
                )
            )
            while !container.isAtEnd {
                guard decoded.count < BackupReaderExtensionState.maximumLegacySources else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Legacy Reader source metadata is too large."
                    )
                }
                decoded.append(try container.decode(BackupLegacyAidokuSourceMetadata.self))
            }
            values = decoded
        }
    }
}

#if !os(tvOS)
enum BackupReaderExtensionStateError: LocalizedError {
    case unsafeMetadata
    case unreadableMetadata
    case restoreVerificationFailed

    var errorDescription: String? {
        switch self {
        case .unsafeMetadata:
            return "Reader Extension metadata contained a non-portable or unsafe field."
        case .unreadableMetadata:
            return "Reader Extension metadata could not be decoded."
        case .restoreVerificationFailed:
            return "Reader Extension metadata did not verify after persistence."
        }
    }
}

extension BackupReaderExtensionState {
    static let legacyAidokuSourcesStorageKey = "readerExtensions.legacyAidokuSources.v1"

    init(
        snapshot: ReaderExtensionBackupSnapshot,
        legacyAidokuSources: [BackupLegacyAidokuSourceMetadata] = []
    ) throws {
        guard snapshot.repositories.count <= Self.maximumRepositories,
              snapshot.installedSources.count <= Self.maximumInstalledSources,
              legacyAidokuSources.count <= Self.maximumLegacySources else {
            throw BackupReaderExtensionStateError.unsafeMetadata
        }
        let portableSnapshot = ReaderExtensionBackupSnapshot(
            repositories: snapshot.repositories,
            installedSources: snapshot.installedSources.map { $0.metadataForBackup() },
            showMatureSources: snapshot.showMatureSources,
            autoUpdateSources: snapshot.autoUpdateSources,
            lastAutoUpdate: snapshot.lastAutoUpdate
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(portableSnapshot)
        guard let safeMetadata = Self.sanitizedMetadataJSON(encoded) else {
            throw BackupReaderExtensionStateError.unsafeMetadata
        }
        self.init(
            metadataJSON: safeMetadata,
            installedSourceCount: portableSnapshot.installedSources.count,
            legacyAidokuSources: legacyAidokuSources,
            showMatureSources: portableSnapshot.showMatureSources,
            autoUpdateSources: portableSnapshot.autoUpdateSources,
            lastAutoUpdate: portableSnapshot.lastAutoUpdate
        )
    }

    static func capture(
        from store: UserDefaults,
        preferenceStore: UserDefaults? = nil
    ) throws -> Self {
        let snapshot = try ReaderExtensionPersistence.backupSnapshot(
            from: store,
            preferenceStore: preferenceStore
        )
        let legacySources: [BackupLegacyAidokuSourceMetadata]
        if let data = store.data(forKey: legacyAidokuSourcesStorageKey) {
            do {
                legacySources = try Self.decodeLegacySources(from: data)
            } catch {
                throw BackupReaderExtensionStateError.unreadableMetadata
            }
        } else {
            legacySources = []
        }
        return try Self(snapshot: snapshot, legacyAidokuSources: legacySources)
    }

    func runtimeSnapshot() throws -> ReaderExtensionBackupSnapshot {
        if let metadataJSON {
            guard Self.sanitizedMetadataJSON(metadataJSON) != nil,
                  let decoded = try? JSONDecoder().decode(
                      ReaderExtensionBackupSnapshot.self,
                      from: metadataJSON
                  ) else {
                throw BackupReaderExtensionStateError.unreadableMetadata
            }
            return ReaderExtensionBackupSnapshot(
                repositories: Array(decoded.repositories.prefix(Self.maximumRepositories)),
                installedSources: Array(
                    decoded.installedSources
                        .map { $0.metadataForBackup() }
                        .prefix(Self.maximumInstalledSources)
                ),
                showMatureSources: decoded.showMatureSources,
                autoUpdateSources: decoded.autoUpdateSources,
                lastAutoUpdate: decoded.lastAutoUpdate
            )
        }
        guard installedSourceCount == 0 else {
            throw BackupReaderExtensionStateError.unreadableMetadata
        }
        return ReaderExtensionBackupSnapshot(
            repositories: [],
            installedSources: [],
            showMatureSources: showMatureSources,
            autoUpdateSources: autoUpdateSources,
            lastAutoUpdate: lastAutoUpdate
        )
    }

    /// Portable backups intentionally contain no executable bytes and mark
    /// every source for revalidation. When applying a recurring cloud/manual
    /// snapshot on a device that already has the *same* verified software,
    /// retain only that device-local runtime state. A new device or any change
    /// to code provenance, license, scope, parser configuration, capabilities,
    /// or preference schema remains inert until its repository is revalidated.
    static func mergingVerifiedLocalRuntime(
        into portable: ReaderExtensionBackupSnapshot,
        localSources: [ReaderExtensionInstalledSource]
    ) -> ReaderExtensionBackupSnapshot {
        let localByID = Dictionary(localSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = portable
        result.installedSources = portable.installedSources.map { incoming in
            guard let local = localByID[incoming.id],
                  localRuntimeCanBeRetained(local),
                  runtimeIdentityMatches(incoming, local) else {
                return incoming
            }
            var merged = incoming
            merged.activeContentDigest = local.activeContentDigest
            merged.rollbackContentDigest = local.rollbackContentDigest
            merged.rollbackSourceSnapshot = local.rollbackSourceSnapshot
            merged.declaredDomains = local.declaredDomains
            merged.requiresReinstall = false
            merged.lastError = nil
            return merged
        }
        return result
    }

    private static func localRuntimeCanBeRetained(
        _ source: ReaderExtensionInstalledSource
    ) -> Bool {
        guard !source.requiresReinstall,
              source.implementation != .unsupportedNative,
              source.license.kind.permitsInstallation else { return false }
        if source.implementation == .javascript {
            guard let digest = source.activeContentDigest,
                  digest.count == 64,
                  digest.allSatisfy(\.isHexDigit) else { return false }
        }
        return true
    }

    private static func runtimeIdentityMatches(
        _ incoming: ReaderExtensionInstalledSource,
        _ local: ReaderExtensionInstalledSource
    ) -> Bool {
        func sameURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none): return true
            case (.some(let lhs), .some(let rhs)):
                return ReaderExtensionURLCanonicalizer.canonicalString(lhs)
                    == ReaderExtensionURLCanonicalizer.canonicalString(rhs)
            default: return false
            }
        }

        return incoming.id == local.id
            && incoming.upstreamID == local.upstreamID
            && incoming.repositoryID == local.repositoryID
            && sameURL(incoming.repositoryURL, local.repositoryURL)
            && sameURL(incoming.baseURL, local.baseURL)
            && sameURL(incoming.apiURL, local.apiURL)
            && sameURL(incoming.sourceCodeURL, local.sourceCodeURL)
            && incoming.language.lowercased() == local.language.lowercased()
            && incoming.languageSelectionVersion == local.languageSelectionVersion
            && incoming.mediaType == local.mediaType
            && incoming.implementation == local.implementation
            && incoming.version == local.version
            && incoming.maturity == local.maturity
            && incoming.license.provenanceFingerprint == local.license.provenanceFingerprint
            && incoming.hasCloudflare == local.hasCloudflare
            && incoming.dateFormat == local.dateFormat
            && incoming.dateFormatLocale == local.dateFormatLocale
            && incoming.additionalParameters == local.additionalParameters
            && incoming.codeProvenanceFingerprint == local.codeProvenanceFingerprint
            && incoming.runtimeCapabilities == local.runtimeCapabilities
            && incoming.preferenceSchemaFingerprint == local.preferenceSchemaFingerprint
            && incoming.secretPreferenceKeys == local.secretPreferenceKeys
    }

    func restore(
        to store: UserDefaults,
        preferenceStore: UserDefaults? = nil,
        postRestoreVerification: (() throws -> Void)? = nil
    ) throws {
        let portableSnapshot = try runtimeSnapshot()
        let localSources: [ReaderExtensionInstalledSource]
        if let persisted = try? ReaderExtensionPersistence.loadInstalledSources(from: store),
           let contentStore = try? ReaderExtensionContentStore() {
            // Reuse the runtime's exact-byte/shape reconciliation before any
            // local state is treated as trusted. Missing/corrupt JS or invalid
            // metadata becomes inert instead of being carried through sync.
            localSources = ReaderExtensionPersistence.reconcileExecutableContent(
                persisted,
                contentStore: contentStore
            ).sources
        } else {
            localSources = []
        }
        let legacy = Self.sanitizedLegacySources(legacyAidokuSources)
        let encodedLegacy = try JSONEncoder().encode(legacy)
        guard encodedLegacy.count <= Self.maximumMetadataBytes else {
            throw BackupReaderExtensionStateError.unsafeMetadata
        }

        let metadataKeys = [
            ReaderExtensionPersistence.repositoriesKey,
            ReaderExtensionPersistence.installedSourcesKey,
            Self.legacyAidokuSourcesStorageKey
        ]
        let global = UserDefaults.standard
        let globalKeys = [
            ReaderExtensionPersistence.showMatureSourcesKey,
            ReaderExtensionPersistence.autoUpdateSourcesKey,
            ReaderExtensionPersistence.lastAutoUpdateKey
        ]
        let previousMetadataValues = metadataKeys.map { ($0, store.object(forKey: $0)) }
        let previousGlobalValues = globalKeys.map { ($0, global.object(forKey: $0)) }
        let previousPreferenceOverlay = preferenceStore.map {
            (
                data: $0.object(forKey: ReaderExtensionPersistence.preferenceOverlayKey),
                marker: $0.object(forKey: ReaderExtensionPersistence.preferenceOverlayMigrationKey)
            )
        }
        do {
            try ReaderExtensionPersistence.restorePortableMetadata(
                portableSnapshot,
                retainingVerifiedRuntimeFrom: localSources,
                to: store,
                preferenceStore: preferenceStore
            )
            if legacy.isEmpty {
                store.removeObject(forKey: Self.legacyAidokuSourcesStorageKey)
            } else {
                store.set(encodedLegacy, forKey: Self.legacyAidokuSourcesStorageKey)
            }
            let verification = try ReaderExtensionPersistence.backupSnapshot(
                from: store,
                preferenceStore: preferenceStore
            )
            let expected = try Self(
                snapshot: portableSnapshot,
                legacyAidokuSources: legacy
            ).runtimeSnapshot()
            let restoredLegacy: [BackupLegacyAidokuSourceMetadata]
            if let data = store.data(forKey: Self.legacyAidokuSourcesStorageKey) {
                restoredLegacy = try Self.decodeLegacySources(from: data)
            } else {
                restoredLegacy = []
            }
            guard ReaderExtensionPersistence.metadataSnapshotsArePersistenceEquivalent(
                verification,
                expected
            ),
                  Self.sanitizedLegacySources(restoredLegacy) == legacy else {
                throw BackupReaderExtensionStateError.restoreVerificationFailed
            }
            try postRestoreVerification?()
        } catch {
            for (key, value) in previousMetadataValues {
                if let value {
                    store.set(value, forKey: key)
                } else {
                    store.removeObject(forKey: key)
                }
            }
            for (key, value) in previousGlobalValues {
                if let value {
                    global.set(value, forKey: key)
                } else {
                    global.removeObject(forKey: key)
                }
            }
            if let preferenceStore, let previousPreferenceOverlay {
                if let value = previousPreferenceOverlay.data {
                    preferenceStore.set(value, forKey: ReaderExtensionPersistence.preferenceOverlayKey)
                } else {
                    preferenceStore.removeObject(forKey: ReaderExtensionPersistence.preferenceOverlayKey)
                }
                if let value = previousPreferenceOverlay.marker {
                    preferenceStore.set(value, forKey: ReaderExtensionPersistence.preferenceOverlayMigrationKey)
                } else {
                    preferenceStore.removeObject(forKey: ReaderExtensionPersistence.preferenceOverlayMigrationKey)
                }
            }
            _ = store.synchronize()
            _ = global.synchronize()
            if let preferenceStore { _ = preferenceStore.synchronize() }
            throw error
        }
    }
}

struct ReaderExtensionLegacyItemReference: Identifiable, Hashable, Sendable {
    let legacySourceID: String
    let legacyItemKey: String
    let title: String?
    let author: String?
    let coverURL: String?
    let occurrenceCount: Int

    var id: String {
        ReaderExtensionAidokuMigration.legacyStableKey(
            sourceID: legacySourceID,
            itemKey: legacyItemKey
        )
    }
}

struct ReaderExtensionLegacyReconnectCandidate: Identifiable, Hashable, Sendable {
    let legacySource: BackupLegacyAidokuSourceMetadata
    let installedSource: ReaderExtensionInstalledSource
    let matchesUpstreamSourceID: Bool
    let matchesOriginHost: Bool
    let matchesLanguage: Bool
    let matchesSourceName: Bool

    var id: String {
        "\(legacySource.id)->\(installedSource.id.rawValue)"
    }

    /// Automatic source mapping is deliberately conservative. Item mapping still requires
    /// an explicit canonical-key/detail verifier before any durable route is changed.
    var isStrongUniqueMatchCandidate: Bool {
        matchesUpstreamSourceID && matchesOriginHost && matchesLanguage
    }
}

struct ReaderExtensionLegacyItemResolution: Hashable, Sendable {
    let legacyItemKey: String
    let readerExtensionItemKey: String

    init(legacyItemKey: String, readerExtensionItemKey: String) {
        self.legacyItemKey = legacyItemKey
        self.readerExtensionItemKey = readerExtensionItemKey
    }
}

/// What a verifier learned about one legacy title. `absent` is a definitive
/// answer â€” the replacement source responded and does not carry the title â€” so
/// its route is kept and marked unavailable rather than blocking the whole
/// source. `interrupted` means the source could not answer at all right now, so
/// a later attempt can still succeed and nothing may be committed yet.
enum ReaderExtensionLegacyItemVerification: Hashable, Sendable {
    case resolved(String)
    case absent
    case interrupted
}

struct ReaderExtensionLegacyReconnectProgress: Equatable, Sendable {
    let checked: Int
    let total: Int
    let resolved: Int
}

struct ReaderExtensionLegacyReconnectReport: Equatable, Sendable {
    let legacySourceID: String
    let installedSourceID: ReaderExtensionSourceID
    let itemCount: Int
    let routeCount: Int
    let changedStoreCount: Int
    /// The legacy item keys deliberately left as `aidoku` routes because the
    /// replacement source answered that it does not carry them. The caller
    /// needs the keys, not just the count, to mark exactly those titles as
    /// confirmed absent rather than merely not-yet-reconnected.
    let retainedItemKeys: Set<String>

    var retainedItemCount: Int { retainedItemKeys.count }

    init(
        legacySourceID: String,
        installedSourceID: ReaderExtensionSourceID,
        itemCount: Int,
        routeCount: Int,
        changedStoreCount: Int,
        retainedItemKeys: Set<String> = []
    ) {
        self.legacySourceID = legacySourceID
        self.installedSourceID = installedSourceID
        self.itemCount = itemCount
        self.routeCount = routeCount
        self.changedStoreCount = changedStoreCount
        self.retainedItemKeys = retainedItemKeys
    }
}

enum ReaderExtensionLegacyReconnectError: LocalizedError {
    case unreadableProfileRoster
    case unreadableStore(String)
    case storeTooLarge(String)
    case invalidSourceIdentity
    case installedSourceNotFound
    case itemVerificationRequired(String)
    case itemVerificationInterrupted(resolved: Int, remaining: Int)
    case noItemsResolved
    case conflictingItemResolution(String)
    case storeChangedDuringVerification(String)
    case rewriteVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableProfileRoster:
            return "Reader source reconnection is paused because the profile roster is unreadable."
        case .unreadableStore(let label):
            return "Reader source reconnection is paused because \(label) is unreadable."
        case .storeTooLarge(let label):
            return "Reader source reconnection is paused because \(label) exceeds the safety limit."
        case .invalidSourceIdentity:
            return "The selected Reader source has an invalid identity."
        case .installedSourceNotFound:
            return "The selected Reader source is no longer installed."
        case .itemVerificationRequired:
            return "Every legacy title must be verified against the replacement source before reconnecting."
        case .itemVerificationInterrupted(let resolved, let remaining):
            return "The replacement source stopped answering with \(remaining) title\(remaining == 1 ? "" : "s") left to check. \(resolved) already matched and \(resolved == 1 ? "was" : "were") saved, so trying again picks up where this left off."
        case .noItemsResolved:
            return "None of the saved titles could be found on the replacement source, so nothing was changed."
        case .conflictingItemResolution:
            return "The replacement source returned conflicting title identities."
        case .storeChangedDuringVerification:
            return "Reader data changed while the source was being verified. Try reconnecting again."
        case .rewriteVerificationFailed:
            return "The reconnected Reader data could not be verified, so the original data was restored."
        }
    }

    /// Progress survives these, so the caller should invite a retry rather than
    /// report the source as permanently unmigratable.
    var isResumable: Bool {
        switch self {
        case .itemVerificationInterrupted, .storeChangedDuringVerification:
            return true
        default:
            return false
        }
    }
}

/// A format-preserving, model-independent route transformer used by migration and tests.
/// It only rewrites dictionaries in a `route` field (or an exact top-level route object),
/// plus the separate Reader download `provider` metadata. Stable IDs and `routeKey` fields
/// are never rewritten.
enum ReaderExtensionLegacyRouteRewriter {
    /// What to do with a route whose legacy item key has no verified
    /// replacement. `require` is the original all-or-nothing contract. `retain`
    /// leaves that route byte-identical so a source where a handful of titles
    /// no longer exist can still migrate the rest; the retained routes stay
    /// `aidoku` and are marked unavailable by the migration rescan.
    enum UnresolvedItemPolicy: Hashable, Sendable {
        case require
        case retain
    }

    struct Mapping: Hashable, Sendable {
        let legacySourceID: String
        let installedSourceID: ReaderExtensionSourceID
        let itemKeys: [String: String]
        let mediaType: ReaderExtensionMediaType
        let unresolvedItems: UnresolvedItemPolicy

        init(
            legacySourceID: String,
            installedSourceID: ReaderExtensionSourceID,
            itemKeys: [String: String],
            mediaType: ReaderExtensionMediaType,
            unresolvedItems: UnresolvedItemPolicy = .require
        ) {
            self.legacySourceID = legacySourceID
            self.installedSourceID = installedSourceID
            self.itemKeys = itemKeys
            self.mediaType = mediaType
            self.unresolvedItems = unresolvedItems
        }
    }

    struct Result: Sendable {
        let data: Data
        let routeCount: Int
        let providerCount: Int
        let retainedCount: Int

        init(data: Data, routeCount: Int, providerCount: Int, retainedCount: Int = 0) {
            self.data = data
            self.routeCount = routeCount
            self.providerCount = providerCount
            self.retainedCount = retainedCount
        }
    }

    private static let maximumDocumentBytes = 32 * 1_024 * 1_024
    private static let maximumDepth = 64
    private static let maximumContainerEntries = 20_256
    private static let maximumTotalTokens = 1_000_000
    private static let maximumStringBytes = 64 * 1_024
    private static let maximumItemKeyBytes = 8 * 1_024

    static func references(
        in data: Data,
        legacySourceID: String? = nil
    ) throws -> [ReaderExtensionLegacyItemReference] {
        let object = try decodedObject(from: data, label: "Reader metadata")
        return try references(in: object, legacySourceID: legacySourceID)
    }

    private static func references(
        in object: Any,
        legacySourceID: String? = nil
    ) throws -> [ReaderExtensionLegacyItemReference] {
        var occurrences: [(sourceID: String, itemKey: String, title: String?, author: String?, coverURL: String?)] = []
        try collectReferences(
            from: object,
            parentKey: nil,
            enclosingDictionary: nil,
            legacySourceID: legacySourceID,
            depth: 0,
            into: &occurrences
        )

        var grouped: [String: ReaderExtensionLegacyItemReference] = [:]
        for occurrence in occurrences {
            let stableKey = ReaderExtensionAidokuMigration.legacyStableKey(
                sourceID: occurrence.sourceID,
                itemKey: occurrence.itemKey
            )
            if let existing = grouped[stableKey] {
                grouped[stableKey] = ReaderExtensionLegacyItemReference(
                    legacySourceID: existing.legacySourceID,
                    legacyItemKey: existing.legacyItemKey,
                    title: existing.title ?? occurrence.title,
                    author: existing.author ?? occurrence.author,
                    coverURL: existing.coverURL ?? occurrence.coverURL,
                    occurrenceCount: existing.occurrenceCount + 1
                )
            } else {
                grouped[stableKey] = ReaderExtensionLegacyItemReference(
                    legacySourceID: occurrence.sourceID,
                    legacyItemKey: occurrence.itemKey,
                    title: occurrence.title,
                    author: occurrence.author,
                    coverURL: occurrence.coverURL,
                    occurrenceCount: 1
                )
            }
        }
        return grouped.values.sorted { lhs, rhs in
            if lhs.legacySourceID == rhs.legacySourceID {
                return lhs.legacyItemKey < rhs.legacyItemKey
            }
            return lhs.legacySourceID < rhs.legacySourceID
        }
    }

    static func rewrite(_ data: Data, mapping: Mapping) throws -> Result {
        guard mapping.installedSourceID.isValid,
              !mapping.legacySourceID.isEmpty,
              !mapping.itemKeys.isEmpty else {
            throw ReaderExtensionLegacyReconnectError.invalidSourceIdentity
        }
        let object = try decodedObject(from: data, label: "Reader metadata")
        var routeCount = 0
        var providerCount = 0
        var retainedCount = 0
        let rewritten = try rewriteValue(
            object,
            parentKey: nil,
            mapping: mapping,
            depth: 0,
            routeCount: &routeCount,
            providerCount: &providerCount,
            retainedCount: &retainedCount
        )
        guard JSONSerialization.isValidJSONObject(rewritten) else {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed("Reader metadata")
        }
        let encoded = try JSONSerialization.data(withJSONObject: rewritten, options: [.sortedKeys])
        guard encoded.count <= maximumDocumentBytes else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge("Reader metadata")
        }
        // Under `.retain` some legacy routes are meant to survive, but only the
        // ones with no *usable* replacement â€” which includes a mapped key the
        // credential guard rejected. Anything else still here means the walk
        // missed a route it was asked to rewrite.
        let remaining = try references(in: encoded, legacySourceID: mapping.legacySourceID)
        let unexpected = remaining.filter {
            validatedMappedItemKey(
                mapping.itemKeys[$0.legacyItemKey],
                legacyItemKey: $0.legacyItemKey
            ) != nil
        }
        guard unexpected.isEmpty,
              mapping.unresolvedItems == .retain || remaining.isEmpty else {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed("Reader metadata")
        }
        return Result(
            data: encoded,
            routeCount: routeCount,
            providerCount: providerCount,
            retainedCount: retainedCount
        )
    }

    static func validate(_ data: Data, label: String) throws {
        let object = try decodedObject(from: data, label: label)
        _ = try references(in: object)
    }

    private static func decodedObject(from data: Data, label: String) throws -> Any {
        guard !data.isEmpty else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
        guard data.count <= maximumDocumentBytes else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(label)
        }
        do {
            try ReaderExtensionJSONPreflight.validate(data, limits: .init(
                maximumBytes: maximumDocumentBytes,
                maximumDepth: maximumDepth,
                maximumContainerEntries: maximumContainerEntries,
                maximumTopLevelEntries: maximumContainerEntries,
                maximumTotalTokens: maximumTotalTokens,
                maximumStringBytes: maximumStringBytes
            ))
        } catch ReaderExtensionError.contentTooLarge {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(label)
        } catch {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
    }

    private static func collectReferences(
        from value: Any,
        parentKey: String?,
        enclosingDictionary: [String: Any]?,
        legacySourceID: String?,
        depth: Int,
        into output: inout [(
            sourceID: String,
            itemKey: String,
            title: String?,
            author: String?,
            coverURL: String?
        )]
    ) throws {
        guard depth <= maximumDepth else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore("Reader metadata")
        }
        if let dictionary = value as? [String: Any] {
            if isRoutePosition(parentKey: parentKey, dictionary: dictionary),
               let identity = legacyIdentity(in: dictionary),
               legacySourceID == nil || identity.sourceID == legacySourceID {
                output.append((
                    identity.sourceID,
                    identity.itemKey,
                    boundedContextString(enclosingDictionary?["title"])
                        ?? boundedContextString(enclosingDictionary?["mangaTitle"]),
                    boundedContextString(enclosingDictionary?["author"]),
                    boundedContextString(enclosingDictionary?["coverURL"])
                        ?? boundedContextString(enclosingDictionary?["cover"])
                ))
            }
            for (key, nested) in dictionary {
                try collectReferences(
                    from: nested,
                    parentKey: key,
                    enclosingDictionary: dictionary,
                    legacySourceID: legacySourceID,
                    depth: depth + 1,
                    into: &output
                )
            }
        } else if let array = value as? [Any] {
            for nested in array {
                try collectReferences(
                    from: nested,
                    parentKey: parentKey,
                    enclosingDictionary: enclosingDictionary,
                    legacySourceID: legacySourceID,
                    depth: depth + 1,
                    into: &output
                )
            }
        }
    }

    private static func rewriteValue(
        _ value: Any,
        parentKey: String?,
        mapping: Mapping,
        depth: Int,
        routeCount: inout Int,
        providerCount: inout Int,
        retainedCount: inout Int
    ) throws -> Any {
        guard depth <= maximumDepth else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore("Reader metadata")
        }
        if var dictionary = value as? [String: Any] {
            if isRoutePosition(parentKey: parentKey, dictionary: dictionary),
               let identity = legacyIdentity(in: dictionary),
               identity.sourceID == mapping.legacySourceID {
                guard let newItemKey = validatedMappedItemKey(
                    mapping.itemKeys[identity.itemKey],
                    legacyItemKey: identity.itemKey
                ) else {
                    guard mapping.unresolvedItems == .retain else {
                        throw ReaderExtensionLegacyReconnectError.itemVerificationRequired(identity.itemKey)
                    }
                    retainedCount += 1
                    return dictionary
                }
                routeCount += 1
                var rewritten: [String: Any] = [
                    "kind": "readerExtension",
                    "source": mapping.installedSourceID.rawValue,
                    "itemKey": newItemKey
                ]
                // MangaContentRoute's decoder throws on a legacyStableKey that
                // is not trimmed, bounded and control-character free, and a
                // throw there quarantines the whole library store on the next
                // launch. The old Aidoku identifiers are unvalidated, so a key
                // that cannot round-trip is omitted; stableKey then falls back
                // to the readerExtension spelling, which loses nothing.
                if let legacyStableKey = ReaderExtensionAidokuMigration.persistableLegacyStableKey(
                    sourceID: identity.sourceID,
                    itemKey: identity.itemKey
                ) {
                    rewritten["legacyStableKey"] = legacyStableKey
                }
                return rewritten
            }

            if parentKey == "provider",
               let identity = legacyIdentity(in: dictionary),
               identity.sourceID == mapping.legacySourceID {
                if let newItemKey = validatedMappedItemKey(
                    mapping.itemKeys[identity.itemKey],
                    legacyItemKey: identity.itemKey
                ) {
                    dictionary["kind"] = "readerExtension"
                    dictionary["sourceId"] = mapping.installedSourceID.rawValue
                    dictionary["mangaKey"] = newItemKey
                    dictionary["isNovel"] = mapping.mediaType == .novel
                    providerCount += 1
                } else {
                    guard mapping.unresolvedItems == .retain else {
                        throw ReaderExtensionLegacyReconnectError.itemVerificationRequired(identity.itemKey)
                    }
                    retainedCount += 1
                }
            }

            for (key, nested) in dictionary {
                dictionary[key] = try rewriteValue(
                    nested,
                    parentKey: key,
                    mapping: mapping,
                    depth: depth + 1,
                    routeCount: &routeCount,
                    providerCount: &providerCount,
                    retainedCount: &retainedCount
                )
            }
            return dictionary
        }
        if let array = value as? [Any] {
            return try array.map {
                try rewriteValue(
                    $0,
                    parentKey: parentKey,
                    mapping: mapping,
                    depth: depth + 1,
                    routeCount: &routeCount,
                    providerCount: &providerCount,
                    retainedCount: &retainedCount
                )
            }
        }
        return value
    }

    private static func isRoutePosition(
        parentKey: String?,
        dictionary: [String: Any]
    ) -> Bool {
        if parentKey == "route" { return true }
        guard parentKey == nil else { return false }
        let routeKeys = Set(["kind", "sourceId", "mangaKey"])
        return Set(dictionary.keys).isSubset(of: routeKeys)
    }

    private static func legacyIdentity(
        in dictionary: [String: Any]
    ) -> (sourceID: String, itemKey: String)? {
        guard dictionary["kind"] as? String == "aidoku",
              let sourceID = boundedIdentityString(dictionary["sourceId"]),
              let itemKey = boundedIdentityString(dictionary["mangaKey"]) else {
            return nil
        }
        return (sourceID, itemKey)
    }

    private static func boundedIdentityString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumItemKeyBytes else { return nil }
        return trimmed
    }

    private static func validatedMappedItemKey(
        _ value: String?,
        legacyItemKey: String
    ) -> String? {
        guard let value = boundedIdentityString(value) else { return nil }
        // Reject a resolver accidentally returning a complete stable key instead of the
        // provider's canonical item key.
        guard value != ReaderExtensionAidokuMigration.legacyStableKey(
            sourceID: "",
            itemKey: legacyItemKey
        ), !value.hasPrefix("aidoku:") else { return nil }
        // Reconnect rewrites the provider-facing item key into ordinary
        // library, progress, tracker, and download metadata. Apply the same
        // credential-bearing URL guard used for newly discovered items so a
        // provider cannot persist userinfo or signed/token query values while
        // the separate legacyStableKey continues to preserve the exact old
        // `aidoku:<source>:<item>` identity.
        return ReaderExtensionSecurityPolicy.persistableProviderContentKey(value)
    }

    private static func boundedContextString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(2_048))
    }
}

/// A resumable record of what the replacement source has already said about each
/// legacy title. Verifying one title costs up to eight sequential provider
/// requests, so a 200-title source is ~1,600 of them; before this existed a
/// single rate limit part-way through discarded every already-matched title and
/// the retry started from zero.
///
/// Nothing here is authoritative. Every cached key is revalidated by
/// `ReaderExtensionLegacyRouteRewriter.validatedMappedItemKey` before it can
/// reach a route, and an unreadable ledger is discarded rather than quarantined
/// â€” losing a cache only costs time, so it must never be able to block a
/// migration the way an unreadable store does.
struct ReaderExtensionReconnectLedger: Codable, Equatable, Sendable {
    struct SourceRecord: Codable, Equatable, Sendable {
        var resolved: [String: String] = [:]
        var absent: [String: Date] = [:]
        var interruptions: [String: Int] = [:]
        /// The exact executable these answers came from. `ReaderExtensionSourceID`
        /// is a hash of repository, upstream id, language and media type, so it
        /// survives version bumps, reinstalls and the automatic rollback a
        /// runtime failure triggers â€” replaying a v1.4 mapping onto v1.3 would
        /// repoint the library at keys that source cannot open.
        var sourceFingerprint: String?
        var updatedAt = Date(timeIntervalSince1970: 0)

        var entryCount: Int { resolved.count + absent.count + interruptions.count }
    }

    var records: [String: SourceRecord] = [:]
}

enum ReaderExtensionReconnectLedgerStore {
    static let storageBase = "readerExtensions.legacyReconnectLedger.v1"
    static let maximumPairs = 32
    static let maximumEntriesPerPair = 20_000
    static let maximumKeyBytes = 8 * 1_024
    /// A title missing today can be added tomorrow, so a definitive "absent"
    /// only suppresses re-checking for a week.
    static let absentRecheckInterval: TimeInterval = 7 * 24 * 60 * 60

    struct Handle {
        let defaults: UserDefaults
        let profileID: UUID

        init(defaults: UserDefaults, profileID: UUID) {
            self.defaults = defaults
            self.profileID = profileID
        }
    }

    static func storageKey(for profileID: UUID) -> String {
        ProfileScopedStorage.defaultsKey(base: storageBase, profileID: profileID)
    }

    static func pairKey(
        legacySourceID: String,
        installedSourceID: ReaderExtensionSourceID
    ) -> String {
        "\(legacySourceID)\u{001F}\(installedSourceID.rawValue)"
    }

    static func load(from store: UserDefaults, profileID: UUID) -> ReaderExtensionReconnectLedger {
        guard let data = store.data(forKey: storageKey(for: profileID)), !data.isEmpty else {
            return ReaderExtensionReconnectLedger()
        }
        guard let decoded = try? JSONDecoder().decode(
            ReaderExtensionReconnectLedger.self,
            from: data
        ) else {
            ReaderLogger.shared.log(
                "ReaderExtensionReconnectLedger: discarded an unreadable verification cache; titles will be rechecked",
                type: "Reader"
            )
            return ReaderExtensionReconnectLedger()
        }
        return decoded
    }

    static func fingerprint(of source: ReaderExtensionInstalledSource) -> String {
        "\(source.version)\u{001F}\(source.activeContentDigest ?? "")"
    }

    static func record(
        in ledger: ReaderExtensionReconnectLedger,
        legacySourceID: String,
        installedSourceID: ReaderExtensionSourceID,
        matching installedSource: ReaderExtensionInstalledSource? = nil
    ) -> ReaderExtensionReconnectLedger.SourceRecord {
        let key = pairKey(legacySourceID: legacySourceID, installedSourceID: installedSourceID)
        guard let stored = ledger.records[key] else {
            return ReaderExtensionReconnectLedger.SourceRecord()
        }
        guard let installedSource else { return stored }
        guard stored.sourceFingerprint == fingerprint(of: installedSource) else {
            ReaderLogger.shared.log(
                "ReaderExtensionReconnectLedger: dropped cached verifications from a different build of the replacement source",
                type: "Reader"
            )
            return ReaderExtensionReconnectLedger.SourceRecord()
        }
        return stored
    }

    static func isKnownAbsent(
        _ legacyItemKey: String,
        in record: ReaderExtensionReconnectLedger.SourceRecord,
        now: Date = Date()
    ) -> Bool {
        guard let checkedAt = record.absent[legacyItemKey] else { return false }
        let age = now.timeIntervalSince(checkedAt)
        return age >= 0 && age < absentRecheckInterval
    }

    @discardableResult
    static func save(
        _ record: ReaderExtensionReconnectLedger.SourceRecord,
        legacySourceID: String,
        installedSourceID: ReaderExtensionSourceID,
        matching installedSource: ReaderExtensionInstalledSource? = nil,
        using handle: Handle,
        now: Date = Date()
    ) -> Bool {
        var ledger = load(from: handle.defaults, profileID: handle.profileID)
        var stamped = bounded(record)
        stamped.updatedAt = now
        if let installedSource { stamped.sourceFingerprint = fingerprint(of: installedSource) }
        let key = pairKey(legacySourceID: legacySourceID, installedSourceID: installedSourceID)
        if stamped.entryCount == 0 {
            ledger.records[key] = nil
        } else {
            ledger.records[key] = stamped
        }
        if ledger.records.count > maximumPairs {
            let survivors = ledger.records
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(maximumPairs)
            ledger.records = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
        }
        let storageKey = storageKey(for: handle.profileID)
        guard !ledger.records.isEmpty else {
            handle.defaults.removeObject(forKey: storageKey)
            return true
        }
        guard let data = try? JSONEncoder().encode(ledger) else {
            ReaderLogger.shared.log(
                "ReaderExtensionReconnectLedger: could not encode the verification cache; the next attempt restarts",
                type: "Reader"
            )
            return false
        }
        handle.defaults.set(data, forKey: storageKey)
        return true
    }

    static func forget(
        legacySourceID: String,
        installedSourceID: ReaderExtensionSourceID,
        using handle: Handle
    ) {
        save(
            ReaderExtensionReconnectLedger.SourceRecord(),
            legacySourceID: legacySourceID,
            installedSourceID: installedSourceID,
            using: handle
        )
    }

    private static func bounded(
        _ record: ReaderExtensionReconnectLedger.SourceRecord
    ) -> ReaderExtensionReconnectLedger.SourceRecord {
        var trimmed = record
        trimmed.resolved = trimmed.resolved.filter { isStorableKey($0.key) && isStorableKey($0.value) }
        trimmed.absent = trimmed.absent.filter { isStorableKey($0.key) }
        trimmed.interruptions = trimmed.interruptions.filter { isStorableKey($0.key) && $0.value > 0 }
        // Resolved keys are the expensive ones to rediscover, so the retry
        // counters and then the absent entries give way first when a
        // pathological store overflows the bound.
        if trimmed.entryCount > maximumEntriesPerPair {
            trimmed.interruptions = [:]
        }
        if trimmed.entryCount > maximumEntriesPerPair {
            let absentBudget = max(0, maximumEntriesPerPair - trimmed.resolved.count)
            trimmed.absent = Dictionary(
                uniqueKeysWithValues: trimmed.absent
                    .sorted { $0.value > $1.value }
                    .prefix(absentBudget)
                    .map { ($0.key, $0.value) }
            )
        }
        if trimmed.resolved.count > maximumEntriesPerPair {
            trimmed.resolved = Dictionary(
                uniqueKeysWithValues: trimmed.resolved
                    .sorted { $0.key < $1.key }
                    .prefix(maximumEntriesPerPair)
                    .map { ($0.key, $0.value) }
            )
            trimmed.absent = [:]
        }
        return trimmed
    }

    private static func isStorableKey(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumKeyBytes
    }
}

/// A bounded write-ahead journal for the multi-store reconnect transaction. The journal is
/// durably written and re-read before any store changes. If the process stops mid-transaction,
/// recovery rolls a prepared transaction back or a committed transaction forward, but only
/// after confirming every current value is a recorded original or replacement.
enum ReaderExtensionReconnectTransactionJournal {
    private enum Phase: String, Codable {
        case prepared
        case committed
    }

    enum Value: Codable, Equatable, Sendable {
        case absent
        case data(Data)
        case string(String)
    }

    enum Location: Codable, Hashable, Sendable {
        case standardDefaults(key: String)
        case file(path: String)
        case metadataDefaults(scope: String, key: String)
    }

    struct Entry: Codable, Equatable, Sendable {
        let location: Location
        let original: Value
        let replacement: Value
    }

    private struct Record: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let createdAt: Date
        let phase: Phase
        let entries: [Entry]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case transactionID
            case createdAt
            case phase
            case entries
        }

        init(
            schemaVersion: Int,
            transactionID: UUID,
            createdAt: Date,
            phase: Phase,
            entries: [Entry]
        ) {
            self.schemaVersion = schemaVersion
            self.transactionID = transactionID
            self.createdAt = createdAt
            self.phase = phase
            self.entries = entries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            transactionID = try container.decode(UUID.self, forKey: .transactionID)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            entries = try container.decode([Entry].self, forKey: .entries)
            // Version 1 journals predate the commit marker. Treating them as prepared
            // preserves their original fail-safe rollback behavior.
            phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .prepared
        }
    }

    static let maximumJournalBytes = 128 * 1_024 * 1_024
    static let maximumEntryCount = 20_256
    private static let maximumLocationBytes = 4 * 1_024
    private static let maximumStringBytes = 16 * 1_024
    private static let maximumValueBytes = 32 * 1_024 * 1_024

    static func prepare(entries: [Entry], at url: URL) throws {
        guard !entries.isEmpty, entries.count <= maximumEntryCount,
              Set(entries.map(\.location)).count == entries.count else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                "Reader reconnect transaction"
            )
        }
        try validate(entries)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ReaderExtensionLegacyReconnectError.storeChangedDuringVerification(
                "Reader reconnect transaction"
            )
        }

        let record = Record(
            schemaVersion: 2,
            transactionID: UUID(),
            createdAt: Date(),
            phase: .prepared,
            entries: entries
        )

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedDirectory.setResourceValues(values)
        do {
            try write(record, at: url)
            let persisted = try loadRecord(at: url)
            guard persisted.transactionID == record.transactionID,
                  persisted.phase == .prepared,
                  persisted.entries == entries else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    "Reader reconnect transaction"
                )
            }
        } catch let error as ReaderExtensionLegacyReconnectError {
            try? FileManager.default.removeItem(at: url)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                "Reader reconnect transaction"
            )
        }
    }

    /// Durably records the transaction decision before its final target checkpoint. If the
    /// process stops after this marker reaches disk, recovery completes every replacement;
    /// without it, recovery restores every original value.
    static func markCommitted(at url: URL) throws {
        let record = try loadRecord(at: url)
        if record.phase == .committed { return }
        let committed = Record(
            schemaVersion: 2,
            transactionID: record.transactionID,
            createdAt: record.createdAt,
            phase: .committed,
            entries: record.entries
        )
        do {
            try write(committed, at: url)
            let persisted = try loadRecord(at: url)
            guard persisted.transactionID == committed.transactionID,
                  persisted.phase == .committed,
                  persisted.entries == committed.entries else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    "Reader reconnect transaction"
                )
            }
        } catch let error as ReaderExtensionLegacyReconnectError {
            throw error
        } catch {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                "Reader reconnect transaction"
            )
        }
    }

    static func recoverIfPresent(
        at url: URL,
        read: (Location) throws -> Value,
        apply: (Value, Location) throws -> Void
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let record = try loadRecord(at: url)

        // Validate the entire transaction before touching a single location.
        for entry in record.entries {
            let current = try read(entry.location)
            guard current == entry.original || current == entry.replacement else {
                throw ReaderExtensionLegacyReconnectError.storeChangedDuringVerification(
                    "Reader reconnect transaction"
                )
            }
        }
        let shouldCommit = record.phase == .committed
        let orderedEntries = shouldCommit ? record.entries : Array(record.entries.reversed())
        for entry in orderedEntries {
            let destination = shouldCommit ? entry.replacement : entry.original
            // Re-check at the write boundary as well as in the all-or-nothing preflight.
            // This refuses a newly introduced third state instead of overwriting it with a
            // stale journal value.
            let current = try read(entry.location)
            guard current == entry.original || current == entry.replacement else {
                throw ReaderExtensionLegacyReconnectError.storeChangedDuringVerification(
                    "Reader reconnect transaction"
                )
            }
            if current != destination {
                try apply(destination, entry.location)
            }
        }
        for entry in record.entries {
            let destination = shouldCommit ? entry.replacement : entry.original
            guard try read(entry.location) == destination else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    "Reader reconnect transaction"
                )
            }
        }
        // `apply` is required to durably checkpoint its target. Consequently, once every
        // destination has been re-read, removing and fsyncing the journal cannot expose a
        // mixed transaction after a restart.
        try clear(at: url)
        return true
    }

    private static func loadRecord(at url: URL) throws -> Record {
        let data: Data
        do {
            data = try BoundedLocalStoreReader.read(
                from: url,
                maximumBytes: maximumJournalBytes
            )
        } catch {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(
                "Reader reconnect transaction"
            )
        }
        return try decodeAndValidate(data)
    }

    private static func write(_ record: Record, at url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        guard data.count <= maximumJournalBytes else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                "Reader reconnect transaction"
            )
        }
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        try synchronizeFileAndDirectory(url)
        guard try BoundedLocalStoreReader.read(
            from: url,
            maximumBytes: maximumJournalBytes
        ) == data else {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                "Reader reconnect transaction"
            )
        }
    }

    static func clear(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            try synchronizeDirectory(url.deletingLastPathComponent())
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    "Reader reconnect transaction"
                )
            }
        } catch let error as ReaderExtensionLegacyReconnectError {
            throw error
        } catch {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                "Reader reconnect transaction"
            )
        }
    }

    private static func decodeAndValidate(_ data: Data) throws -> Record {
        guard !data.isEmpty, data.count <= maximumJournalBytes else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                "Reader reconnect transaction"
            )
        }
        let record: Record
        do {
            record = try PropertyListDecoder().decode(Record.self, from: data)
        } catch {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(
                "Reader reconnect transaction"
            )
        }
        guard (record.schemaVersion == 1 || record.schemaVersion == 2),
              record.schemaVersion == 2 || record.phase == .prepared,
              !record.entries.isEmpty,
              record.entries.count <= maximumEntryCount,
              Set(record.entries.map(\.location)).count == record.entries.count else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(
                "Reader reconnect transaction"
            )
        }
        try validate(record.entries)
        return record
    }

    private static func validate(_ entries: [Entry]) throws {
        for entry in entries {
            switch entry.location {
            case .standardDefaults(let key):
                guard isBounded(key, maximum: maximumLocationBytes) else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(
                        "Reader reconnect transaction"
                    )
                }
            case .file(let path):
                guard path.hasPrefix("/"), isBounded(path, maximum: maximumLocationBytes) else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(
                        "Reader reconnect transaction"
                    )
                }
            case .metadataDefaults(let scope, let key):
                guard isBounded(scope, maximum: maximumLocationBytes),
                      isBounded(key, maximum: maximumLocationBytes) else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(
                        "Reader reconnect transaction"
                    )
                }
            }
            try validate(entry.original)
            try validate(entry.replacement)
        }
    }

    private static func validate(_ value: Value) throws {
        switch value {
        case .absent:
            return
        case .data(let data):
            guard data.count <= maximumValueBytes else {
                throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                    "Reader reconnect transaction"
                )
            }
        case .string(let string):
            guard isBounded(string, maximum: maximumStringBytes) else {
                throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                    "Reader reconnect transaction"
                )
            }
        }
    }

    private static func isBounded(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximum
    }

    static func synchronizeFileAndDirectory(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Owns the data-safe Aidoku reconnect seam. It does not perform title matching and it does
/// not contact a provider itself; callers supply canonical item-key verification explicitly.
enum ReaderExtensionLegacyReconnectManager {
    typealias ItemKeyVerifier = @Sendable (
        _ legacyItem: ReaderExtensionLegacyItemReference,
        _ installedSource: ReaderExtensionInstalledSource
    ) async throws -> ReaderExtensionLegacyItemVerification

    typealias ReconnectProgressObserver = @MainActor (ReaderExtensionLegacyReconnectProgress) -> Void

    static let quarantineKey = "readerExtensions.legacyReconnectQuarantine.v1"
    private static let maximumRouteStoreCount = 20_000
    private static let maximumRouteStoreBytes = 32 * 1_024 * 1_024
    private static let maximumTotalRouteStoreBytes = 256 * 1_024 * 1_024
    private static let metadataScopeStandard = "standard"
    private static let metadataScopePrimary = "primary"
    private static let metadataScopeProfilePrefix = "profile:"
    private static let journalFileName = "legacy-reconnect-journal.v1.plist"

    private enum StoreLocation: Hashable {
        case defaults(key: String, label: String)
        case file(url: URL, label: String)

        var label: String {
            switch self {
            case .defaults(_, let label), .file(_, let label): return label
            }
        }
    }

    private struct StoreSnapshot {
        let location: StoreLocation
        let originalData: Data
        let references: [ReaderExtensionLegacyItemReference]
    }

    private struct LegacyMetadataStoreSnapshot {
        let store: UserDefaults
        let journalScope: String
        let label: String
        let originalData: Data?
        let sources: [BackupLegacyAidokuSourceMetadata]
        let selectedHomeSourceID: String?
        let originalInstalledSourcesData: Data?
        let installedSources: [ReaderExtensionInstalledSource]
    }

    private enum PlannedMutationTarget {
        case route(StoreLocation)
        case metadata(store: UserDefaults, key: String, label: String)
    }

    private struct PlannedMutation {
        let target: PlannedMutationTarget
        let journalLocation: ReaderExtensionReconnectTransactionJournal.Location
        let original: ReaderExtensionReconnectTransactionJournal.Value
        let replacement: ReaderExtensionReconnectTransactionJournal.Value
    }

    private static let selectedHomeSourceKey = "kanzenHomeSelectedSourceID"

    private static var transactionJournalURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ReaderExtensions", isDirectory: true)
        return root.appendingPathComponent(journalFileName)
    }

    static func legacySources(
        in store: UserDefaults = ProfileSettingsStore.services
    ) -> [BackupLegacyAidokuSourceMetadata] {
        ReaderExtensionAidokuMigration.legacySources(in: store)
    }

    static func candidates(
        legacySources: [BackupLegacyAidokuSourceMetadata],
        installedSources: [ReaderExtensionInstalledSource]
    ) -> [ReaderExtensionLegacyReconnectCandidate] {
        legacySources.flatMap { legacy in
            installedSources.compactMap { installed in
                let idMatch = canonicalIdentifier(legacy.id)
                    == canonicalIdentifier(installed.upstreamID)
                let legacyHost = canonicalHost(legacy.originHost)
                let installedHosts = Set([
                    installed.baseURL.host,
                    installed.apiURL?.host,
                    installed.sourceCodeURL?.host,
                    installed.repositoryURL.host
                ].compactMap(canonicalHost))
                let hostMatch = legacyHost.map(installedHosts.contains) ?? false
                let legacyLanguages = Set(legacy.languages.compactMap(canonicalLanguage))
                let installedLanguage = canonicalLanguage(installed.language)
                let languageMatch = installedLanguage.map(legacyLanguages.contains) ?? false
                let sourceNameMatch = canonicalSourceName(legacy.name)
                    == canonicalSourceName(installed.name)
                // Aidoku retained the package host (usually the community
                // repository), while Mangayomi IDs are numeric and provider
                // hosts differ. Name + language is therefore useful only as a
                // manual candidate-discovery seam; automatic reconnect still
                // requires the existing strong identity evidence below.
                guard idMatch || (hostMatch && languageMatch)
                        || (sourceNameMatch && languageMatch) else { return nil }
                return ReaderExtensionLegacyReconnectCandidate(
                    legacySource: legacy,
                    installedSource: installed,
                    matchesUpstreamSourceID: idMatch,
                    matchesOriginHost: hostMatch,
                    matchesLanguage: languageMatch,
                    matchesSourceName: sourceNameMatch
                )
            }
        }.sorted { lhs, rhs in
            if lhs.isStrongUniqueMatchCandidate != rhs.isStrongUniqueMatchCandidate {
                return lhs.isStrongUniqueMatchCandidate
            }
            if lhs.legacySource.order != rhs.legacySource.order {
                return lhs.legacySource.order < rhs.legacySource.order
            }
            return lhs.installedSource.sortIndex < rhs.installedSource.sortIndex
        }
    }

    static func uniqueStrongCandidates(
        legacySources: [BackupLegacyAidokuSourceMetadata],
        installedSources: [ReaderExtensionInstalledSource]
    ) -> [ReaderExtensionLegacyReconnectCandidate] {
        let strong = candidates(
            legacySources: legacySources,
            installedSources: installedSources
        ).filter(\.isStrongUniqueMatchCandidate)
        return Dictionary(grouping: strong, by: { $0.legacySource.id })
            .values
            .compactMap { $0.count == 1 ? $0[0] : nil }
            .sorted { $0.legacySource.order < $1.legacySource.order }
    }

    static func legacyItems(sourceID: String) throws -> [ReaderExtensionLegacyItemReference] {
        let snapshots = try routeStoreSnapshots(legacySourceID: sourceID)
        return mergedReferences(snapshots.flatMap(\.references))
    }

    /// Restores an interrupted reconnect before Reader managers consume any partially
    /// rewritten route or source store. Recovery is idempotent and removes the journal only
    /// after every original value has been verified.
    @discardableResult
    static func recoverInterruptedReconnectIfNeeded(
        servicesStore: UserDefaults = ProfileSettingsStore.services
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: transactionJournalURL.path) else {
            return false
        }
        let targets = try journalTargets(servicesStore: servicesStore)
        return try ReaderExtensionReconnectTransactionJournal.recoverIfPresent(
            at: transactionJournalURL,
            read: { location in
                guard let target = targets[location] else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(
                        "Reader reconnect transaction"
                    )
                }
                return try currentValue(for: target)
            },
            apply: { value, location in
                guard let target = targets[location] else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(
                        "Reader reconnect transaction"
                    )
                }
                try applyValue(value, to: target)
            }
        )
    }

    static func markRecoveryQuarantined(_ error: Error) {
        markQuarantined(error)
    }

    @MainActor
    static func reconnect(
        legacySourceID: String,
        to installedSource: ReaderExtensionInstalledSource,
        resolutions: [ReaderExtensionLegacyItemResolution],
        servicesStore: UserDefaults = ProfileSettingsStore.services
    ) throws -> ReaderExtensionLegacyReconnectReport {
        var mapping: [String: String] = [:]
        for resolution in resolutions {
            if let existing = mapping[resolution.legacyItemKey],
               existing != resolution.readerExtensionItemKey {
                throw ReaderExtensionLegacyReconnectError.conflictingItemResolution(
                    resolution.legacyItemKey
                )
            }
            mapping[resolution.legacyItemKey] = resolution.readerExtensionItemKey
        }
        return try reconnectVerified(
            legacySourceID: legacySourceID,
            to: installedSource,
            itemKeys: mapping,
            servicesStore: servicesStore
        )
    }

    /// Verifies every legacy title against the replacement source and commits
    /// what matched. The sweep is resumable: each answer is written to the
    /// ledger as it arrives, so an interrupted run costs only the titles it had
    /// not reached yet. Titles the source definitively does not carry keep their
    /// `aidoku` routes instead of blocking the whole source.
    /// Stopping the sweep this many answers into an unbroken run of "the source
    /// is not responding" is what separates a rate limit from one awkward title.
    static let maximumConsecutiveInterruptions = 3
    /// A title that fails this many times while the source is demonstrably
    /// answering other titles is treated as absent, so one permanently
    /// unanswerable entry cannot block every title behind it forever.
    static let maximumItemInterruptions = 3

    @MainActor
    static func reconnect(
        legacySourceID: String,
        to installedSource: ReaderExtensionInstalledSource,
        servicesStore: UserDefaults = ProfileSettingsStore.services,
        unresolvedItems: ReaderExtensionLegacyRouteRewriter.UnresolvedItemPolicy = .require,
        ledger ledgerHandle: ReaderExtensionReconnectLedgerStore.Handle? = nil,
        progress: ReconnectProgressObserver? = nil,
        verifyItemKey: ItemKeyVerifier
    ) async throws -> ReaderExtensionLegacyReconnectReport {
        let initialSnapshots = try routeStoreSnapshots(legacySourceID: legacySourceID)
        let items = mergedReferences(initialSnapshots.flatMap(\.references))
        let handle = ledgerHandle ?? ReaderExtensionReconnectLedgerStore.Handle(
            defaults: .standard,
            profileID: ProfileManager.shared.activeProfileID
        )
        var record = ReaderExtensionReconnectLedgerStore.record(
            in: ReaderExtensionReconnectLedgerStore.load(
                from: handle.defaults,
                profileID: handle.profileID
            ),
            legacySourceID: legacySourceID,
            installedSourceID: installedSource.id,
            matching: installedSource
        )
        let alreadyMigratedSomething = !record.resolved.isEmpty
        var resolutions = record.resolved
        var checked = 0
        var consecutiveInterruptions = 0
        var interruptedThisRun: [String] = []
        var sourceAnsweredAtLeastOnce = false

        func publishProgress() {
            progress?(ReaderExtensionLegacyReconnectProgress(
                checked: checked,
                total: items.count,
                resolved: items.reduce(into: 0) {
                    if resolutions[$1.legacyItemKey] != nil { $0 += 1 }
                }
            ))
        }

        func persist() {
            ReaderExtensionReconnectLedgerStore.save(
                record,
                legacySourceID: legacySourceID,
                installedSourceID: installedSource.id,
                matching: installedSource,
                using: handle
            )
        }

        publishProgress()
        for item in items {
            let key = item.legacyItemKey
            guard resolutions[key] == nil,
                  !ReaderExtensionReconnectLedgerStore.isKnownAbsent(key, in: record) else {
                checked += 1
                publishProgress()
                continue
            }
            switch try await verifyItemKey(item, installedSource) {
            case .resolved(let resolved):
                resolutions[key] = resolved
                record.resolved[key] = resolved
                record.absent[key] = nil
                record.interruptions[key] = nil
                consecutiveInterruptions = 0
                sourceAnsweredAtLeastOnce = true
            case .absent:
                record.absent[key] = Date()
                record.resolved[key] = nil
                record.interruptions[key] = nil
                resolutions[key] = nil
                consecutiveInterruptions = 0
                sourceAnsweredAtLeastOnce = true
            case .interrupted:
                // Keep going. Stopping at the first one means a single title the
                // source will never answer for hides every title sorted after
                // it from every future run, which is exactly the resumability
                // this is supposed to provide.
                interruptedThisRun.append(key)
                consecutiveInterruptions += 1
            }
            persist()
            checked += 1
            publishProgress()
            if consecutiveInterruptions >= Self.maximumConsecutiveInterruptions { break }
        }

        // An interruption only counts against a title when the source proved it
        // was answering other titles in the same run. Otherwise a rate limit
        // would slowly demote perfectly present titles to absent.
        if sourceAnsweredAtLeastOnce {
            for key in interruptedThisRun {
                let attempts = (record.interruptions[key] ?? 0) + 1
                if attempts >= Self.maximumItemInterruptions {
                    record.interruptions[key] = nil
                    record.absent[key] = Date()
                } else {
                    record.interruptions[key] = attempts
                }
            }
            persist()
        }

        let unverified = items.filter {
            resolutions[$0.legacyItemKey] == nil
                && !ReaderExtensionReconnectLedgerStore.isKnownAbsent($0.legacyItemKey, in: record)
        }
        guard unverified.isEmpty else {
            throw ReaderExtensionLegacyReconnectError.itemVerificationInterrupted(
                resolved: resolutions.count,
                remaining: unverified.count
            )
        }

        // Everything still carrying a legacy route was already answered for in
        // an earlier run, so there is nothing new to commit. Reporting that as a
        // failure would file a source that migrated fine as permanently broken.
        guard items.contains(where: { resolutions[$0.legacyItemKey] != nil }) else {
            guard alreadyMigratedSomething else {
                throw ReaderExtensionLegacyReconnectError.noItemsResolved
            }
            return ReaderExtensionLegacyReconnectReport(
                legacySourceID: legacySourceID,
                installedSourceID: installedSource.id,
                itemCount: 0,
                routeCount: 0,
                changedStoreCount: 0,
                retainedItemKeys: Set(items.map(\.legacyItemKey))
            )
        }

        // The sweep can run for minutes, so a saved title added or a chapter
        // read meanwhile must not throw the whole run away. Under `.retain` it
        // cannot do harm: the transaction re-reads every store, an entry with no
        // verified replacement simply keeps its own route, and each store is
        // still checked byte-for-byte against its recorded original immediately
        // before and after it is written.
        let report = try reconnectVerified(
            legacySourceID: legacySourceID,
            to: installedSource,
            itemKeys: resolutions,
            unresolvedItems: unresolvedItems,
            servicesStore: servicesStore
        )
        if report.retainedItemCount == 0 {
            ReaderExtensionReconnectLedgerStore.forget(
                legacySourceID: legacySourceID,
                installedSourceID: installedSource.id,
                using: handle
            )
        }
        return report
    }

    /// Called by the legacy artifact cleanup gate. Any unreadable profile/route store is
    /// quarantined and keeps old files from being destructively removed.
    static func preflightStoresForCleanup() -> Bool {
        do {
            _ = try recoverInterruptedReconnectIfNeeded()
            _ = try routeStoreSnapshots(legacySourceID: nil)
            _ = try legacyMetadataStoreSnapshots(primary: ProfileSettingsStore.services)
            UserDefaults.standard.removeObject(forKey: quarantineKey)
            return true
        } catch {
            markQuarantined(error)
            return false
        }
    }

    @MainActor
    private static func reconnectVerified(
        legacySourceID: String,
        to installedSource: ReaderExtensionInstalledSource,
        itemKeys: [String: String],
        unresolvedItems: ReaderExtensionLegacyRouteRewriter.UnresolvedItemPolicy = .require,
        servicesStore: UserDefaults
    ) throws -> ReaderExtensionLegacyReconnectReport {
        _ = try recoverInterruptedReconnectIfNeeded(servicesStore: servicesStore)
        guard installedSource.id.isValid else {
            throw ReaderExtensionLegacyReconnectError.invalidSourceIdentity
        }
        let currentSnapshots = try routeStoreSnapshots(legacySourceID: legacySourceID)
        let items = mergedReferences(currentSnapshots.flatMap(\.references))
        let presentKeys = Set(items.map(\.legacyItemKey))
        // A ledger entry for a title that has already been rewritten, or that
        // was removed from the library since it was verified, must not widen
        // what this transaction touches.
        let effectiveItemKeys = itemKeys.filter { presentKeys.contains($0.key) }
        let retainedKeys = presentKeys.subtracting(effectiveItemKeys.keys)
        switch unresolvedItems {
        case .require:
            if let unverified = retainedKeys.sorted().first {
                throw ReaderExtensionLegacyReconnectError.itemVerificationRequired(unverified)
            }
        case .retain:
            guard presentKeys.isEmpty || !effectiveItemKeys.isEmpty else {
                throw ReaderExtensionLegacyReconnectError.noItemsResolved
            }
        }

        let mapping = ReaderExtensionLegacyRouteRewriter.Mapping(
            legacySourceID: legacySourceID,
            installedSourceID: installedSource.id,
            itemKeys: effectiveItemKeys,
            mediaType: installedSource.mediaType,
            unresolvedItems: unresolvedItems
        )
        var mutations: [(snapshot: StoreSnapshot, replacement: Data)] = []
        var routeCount = 0
        for snapshot in currentSnapshots where !snapshot.references.isEmpty {
            let result = try ReaderExtensionLegacyRouteRewriter.rewrite(
                snapshot.originalData,
                mapping: mapping
            )
            if result.routeCount > 0 || result.providerCount > 0 {
                mutations.append((snapshot, result.data))
                routeCount += result.routeCount
            }
        }

        let legacyMetadataStores: [LegacyMetadataStoreSnapshot]
        do {
            legacyMetadataStores = try legacyMetadataStoreSnapshots(
                primary: servicesStore
            )
        } catch {
            markQuarantined(error)
            throw error
        }
        // A sweep runs for minutes, so the replacement can be uninstalled while
        // it is in flight. The installed-sources mutation is planned only for a
        // store that still lists it, so without this the routes would silently
        // be repointed at a source that is gone and can never be offered as a
        // candidate again. Judge that only against stores that actually carry an
        // inventory â€” no inventory anywhere is no evidence either way, not
        // evidence of an uninstall.
        let inventories = legacyMetadataStores.filter { !$0.installedSources.isEmpty }
        guard inventories.isEmpty || inventories.contains(where: { store in
            store.installedSources.contains { $0.id == installedSource.id }
        }) else {
            throw ReaderExtensionLegacyReconnectError.installedSourceNotFound
        }
        // Retained routes still spell `aidoku:<source>`, so that source's entry
        // has to stay in the legacy metadata. Dropping it would leave routes
        // whose source can never be identified again: the leftover scan would
        // find no candidate to offer, and the retry the user is being invited to
        // make would have nothing to match against.
        let transactionMutations = try plannedMutations(
            routeMutations: mutations,
            metadataStores: legacyMetadataStores,
            legacySourceID: legacySourceID,
            installedSource: installedSource,
            retainsLegacySource: !retainedKeys.isEmpty
        )
        for mutation in transactionMutations {
            guard try currentValue(for: mutation.target) == mutation.original else {
                throw ReaderExtensionLegacyReconnectError.storeChangedDuringVerification(
                    mutationLabel(mutation.target)
                )
            }
        }
        try ReaderExtensionReconnectTransactionJournal.prepare(
            entries: transactionMutations.map {
                ReaderExtensionReconnectTransactionJournal.Entry(
                    location: $0.journalLocation,
                    original: $0.original,
                    replacement: $0.replacement
                )
            },
            at: transactionJournalURL
        )
        do {
            for mutation in transactionMutations {
                guard try currentValue(for: mutation.target) == mutation.original else {
                    throw ReaderExtensionLegacyReconnectError.storeChangedDuringVerification(
                        mutationLabel(mutation.target)
                    )
                }
                try applyValue(mutation.replacement, to: mutation.target)
                guard try currentValue(for: mutation.target) == mutation.replacement else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                        mutationLabel(mutation.target)
                    )
                }
            }

            for mutation in mutations {
                guard let persisted = try read(mutation.snapshot.location) else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                        mutation.snapshot.location.label
                    )
                }
                let survivors = Set(
                    try ReaderExtensionLegacyRouteRewriter.references(
                        in: persisted,
                        legacySourceID: legacySourceID
                    ).map(\.legacyItemKey)
                )
                guard survivors.isSubset(of: retainedKeys) else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                        mutation.snapshot.location.label
                    )
                }
                // The store's own reader has to accept what was just written.
                // Without this the rewrite can commit a document the library or
                // download index rejects on the next launch, which quarantines
                // the whole store â€” a rollback here costs nothing by comparison.
                try validatePersistedSchema(persisted, at: mutation.snapshot.location)
            }
            for metadataStore in legacyMetadataStores {
                let remaining = try ReaderExtensionAidokuMigration.validatedLegacySources(
                    in: metadataStore.store
                )
                let stillListed = remaining.contains { $0.id == legacySourceID }
                let shouldStillBeListed = !retainedKeys.isEmpty
                    && metadataStore.sources.contains { $0.id == legacySourceID }
                guard stillListed == shouldStillBeListed else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                        "Reader source metadata"
                    )
                }
            }

            // The durable decision separates rollback from roll-forward recovery. Reapply
            // every replacement after that decision so the journal is only removed once all
            // file and preferences targets have been checkpointed durably.
            try ReaderExtensionReconnectTransactionJournal.markCommitted(
                at: transactionJournalURL
            )
            for mutation in transactionMutations {
                try applyValue(mutation.replacement, to: mutation.target)
                guard try currentValue(for: mutation.target) == mutation.replacement else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                        mutationLabel(mutation.target)
                    )
                }
            }
            try ReaderExtensionReconnectTransactionJournal.clear(
                at: transactionJournalURL
            )
        } catch {
            let transactionError = error
            do {
                _ = try recoverInterruptedReconnectIfNeeded(
                    servicesStore: servicesStore
                )
            } catch {
                markQuarantined(error)
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    "Reader reconnect transaction"
                )
            }
            // If the commit marker was durable, recovery deliberately completed every
            // replacement. Treat that as success; a prepared transaction was restored and
            // must still report the initiating failure.
            let completedCommittedTransaction = (try? transactionMutations.allSatisfy {
                try currentValue(for: $0.target) == $0.replacement
            }) == true
            guard completedCommittedTransaction else {
                markQuarantined(transactionError)
                throw transactionError
            }
        }

        UserDefaults.standard.removeObject(forKey: quarantineKey)
        reloadLiveReaderStores()
        return ReaderExtensionLegacyReconnectReport(
            legacySourceID: legacySourceID,
            installedSourceID: installedSource.id,
            itemCount: effectiveItemKeys.count,
            routeCount: routeCount,
            changedStoreCount: mutations.count,
            retainedItemKeys: retainedKeys
        )
    }

    private static func routeStoreSnapshots(
        legacySourceID: String?
    ) throws -> [StoreSnapshot] {
        do {
            let locations = try storeLocations()
            guard locations.count <= maximumRouteStoreCount else {
                throw ReaderExtensionLegacyReconnectError.storeTooLarge("Reader store index")
            }
            var totalBytes = 0
            var snapshots: [StoreSnapshot] = []
            snapshots.reserveCapacity(locations.count)
            for location in locations {
                guard let data = try read(location) else { continue }
                let (nextTotal, overflow) = totalBytes.addingReportingOverflow(data.count)
                guard !overflow, nextTotal <= maximumTotalRouteStoreBytes else {
                    throw ReaderExtensionLegacyReconnectError.storeTooLarge("Reader stores")
                }
                totalBytes = nextTotal
                try ReaderExtensionLegacyRouteRewriter.validate(data, label: location.label)
                try validatePersistedSchema(data, at: location)
                snapshots.append(StoreSnapshot(
                    location: location,
                    originalData: data,
                    references: try ReaderExtensionLegacyRouteRewriter.references(
                        in: data,
                        legacySourceID: legacySourceID
                    )
                ))
            }
            return snapshots
        } catch {
            markQuarantined(error)
            throw error
        }
    }

    private static func validatePersistedSchema(
        _ data: Data,
        at location: StoreLocation
    ) throws {
        let valid: Bool
        switch location {
        case .defaults(let key, _)
            where key == "mangaLibraryCollections"
                || key.hasPrefix("mangaLibraryCollections."):
            valid = MangaLibraryManager.persistedCollectionsSchemaIsValid(data)

        case .defaults(let key, _)
            where key == "mangaReadingProgress"
                || key.hasPrefix("mangaReadingProgress."):
            valid = MangaReadingProgressManager.persistedProgressSchemaIsValid(data)

        case .file(let url, _)
            where url.lastPathComponent == ".reader_downloads.json":
            valid = ReaderDownloadManager.persistedIndexSchemaIsValid(data)

        case .file(let url, _)
            where url.lastPathComponent == "chapter.json":
            valid = ReaderDownloadManager.persistedChapterManifestSchemaIsValid(data)

        case .file(let url, _)
            where url.lastPathComponent.hasPrefix("UserRatings")
                && url.pathExtension.lowercased() == "json":
            valid = UserRatingManager.persistedStoreSchemaIsValid(data)

        default:
            valid = false
        }
        guard valid else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(location.label)
        }
    }

    private static func legacyMetadataStoreSnapshots(
        primary: UserDefaults
    ) throws -> [LegacyMetadataStoreSnapshot] {
        let manager = ProfileManager.shared
        guard manager.rosterStoreIsReadable else {
            throw ReaderExtensionLegacyReconnectError.unreadableProfileRoster
        }
        let standard = UserDefaults.standard
        let profileStores: [(UUID, UserDefaults)] = manager.profiles.map {
            ($0.id, ProfileSettingsStore.shared.store(for: $0.id))
        }
        func stableScope(for store: UserDefaults) -> String {
            if ObjectIdentifier(store) == ObjectIdentifier(standard) {
                return metadataScopeStandard
            }
            if let profile = profileStores.first(where: {
                ObjectIdentifier($0.1) == ObjectIdentifier(store)
            }) {
                return metadataScopeProfilePrefix + profile.0.uuidString
            }
            return metadataScopePrimary
        }
        var stores: [(UserDefaults, String, String)] = [(
            primary,
            "active Reader source metadata",
            stableScope(for: primary)
        )]
        stores.append((standard, "shared Reader source metadata", metadataScopeStandard))
        stores.append(contentsOf: manager.profiles.map {
            (
                ProfileSettingsStore.shared.store(for: $0.id),
                "Reader source metadata \(ProfileScopedStorage.token(for: $0.id))",
                metadataScopeProfilePrefix + $0.id.uuidString
            )
        })
        var seen = Set<ObjectIdentifier>()
        return try stores.compactMap { store, label, scope in
            guard seen.insert(ObjectIdentifier(store)).inserted else { return nil }
            let selectedValue = store.object(forKey: selectedHomeSourceKey)
            guard selectedValue == nil || selectedValue is String else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            let value = store.object(
                forKey: BackupReaderExtensionState.legacyAidokuSourcesStorageKey
            )
            guard value != nil else {
                let installedSourcesValue = store.object(
                    forKey: ReaderExtensionPersistence.installedSourcesKey
                )
                guard installedSourcesValue == nil || installedSourcesValue is Data else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
                }
                let installedSourcesData = installedSourcesValue as? Data
                let installedSources = try decodedInstalledSources(
                    installedSourcesData,
                    label: label
                )
                return LegacyMetadataStoreSnapshot(
                    store: store,
                    journalScope: scope,
                    label: label,
                    originalData: nil,
                    sources: [],
                    selectedHomeSourceID: selectedValue as? String,
                    originalInstalledSourcesData: installedSourcesData,
                    installedSources: installedSources
                )
            }
            guard let data = value as? Data else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            let decoded: [BackupLegacyAidokuSourceMetadata]
            do {
                decoded = try ReaderExtensionAidokuMigration.validatedLegacySources(data: data)
            } catch {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            let installedSourcesValue = store.object(
                forKey: ReaderExtensionPersistence.installedSourcesKey
            )
            guard installedSourcesValue == nil || installedSourcesValue is Data else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            let installedSourcesData = installedSourcesValue as? Data
            let installedSources = try decodedInstalledSources(
                installedSourcesData,
                label: label
            )
            return LegacyMetadataStoreSnapshot(
                store: store,
                journalScope: scope,
                label: label,
                originalData: data,
                sources: decoded,
                selectedHomeSourceID: selectedValue as? String,
                originalInstalledSourcesData: installedSourcesData,
                installedSources: installedSources
            )
        }
    }

    private static func decodedInstalledSources(
        _ data: Data?,
        label: String
    ) throws -> [ReaderExtensionInstalledSource] {
        guard let data else { return [] }
        guard !data.isEmpty, data.count <= BackupReaderExtensionState.maximumMetadataBytes else {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            try ReaderExtensionPersistence.validateInstalledSourceStoreJSON(
                data,
                maximumBytes: BackupReaderExtensionState.maximumMetadataBytes
            )
            return try decoder.decode([ReaderExtensionInstalledSource].self, from: data)
        } catch {
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
    }

    private static func installedSourcesData(
        _ installedSources: [ReaderExtensionInstalledSource],
        applying legacySource: BackupLegacyAidokuSourceMetadata,
        to sourceID: ReaderExtensionSourceID
    ) throws -> Data {
        var ordered = installedSources.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.id.rawValue < rhs.id.rawValue
        }
        guard let index = ordered.firstIndex(where: { $0.id == sourceID }) else {
            throw ReaderExtensionLegacyReconnectError.installedSourceNotFound
        }
        var replacement = ordered.remove(at: index)
        replacement.enabled = legacySource.isEnabled
        let destination = min(max(legacySource.order, 0), ordered.count)
        ordered.insert(replacement, at: destination)
        for index in ordered.indices { ordered[index].sortIndex = index }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ordered)
        guard data.count <= BackupReaderExtensionState.maximumMetadataBytes else {
            throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                "Reader source metadata"
            )
        }
        return data
    }

    private static func plannedMutations(
        routeMutations: [(snapshot: StoreSnapshot, replacement: Data)],
        metadataStores: [LegacyMetadataStoreSnapshot],
        legacySourceID: String,
        installedSource: ReaderExtensionInstalledSource,
        retainsLegacySource: Bool = false
    ) throws -> [PlannedMutation] {
        var result: [PlannedMutation] = routeMutations.map { mutation in
            let journalLocation: ReaderExtensionReconnectTransactionJournal.Location
            switch mutation.snapshot.location {
            case .defaults(let key, _):
                journalLocation = .standardDefaults(key: key)
            case .file(let url, _):
                journalLocation = .file(path: url.standardizedFileURL.path)
            }
            return PlannedMutation(
                target: .route(mutation.snapshot.location),
                journalLocation: journalLocation,
                original: .data(mutation.snapshot.originalData),
                replacement: .data(mutation.replacement)
            )
        }

        for metadataStore in metadataStores {
            guard let legacySource = metadataStore.sources.first(where: {
                $0.id == legacySourceID
            }) else { continue }

            if !retainsLegacySource {
                let remainingSources = metadataStore.sources.filter { $0.id != legacySourceID }
                let legacyReplacement: ReaderExtensionReconnectTransactionJournal.Value
                if remainingSources.isEmpty {
                    legacyReplacement = .absent
                } else {
                    let data = try JSONEncoder().encode(remainingSources)
                    guard data.count <= BackupReaderExtensionState.maximumMetadataBytes else {
                        throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                            metadataStore.label
                        )
                    }
                    legacyReplacement = .data(data)
                }
                result.append(PlannedMutation(
                    target: .metadata(
                        store: metadataStore.store,
                        key: BackupReaderExtensionState.legacyAidokuSourcesStorageKey,
                        label: metadataStore.label
                    ),
                    journalLocation: .metadataDefaults(
                        scope: metadataStore.journalScope,
                        key: BackupReaderExtensionState.legacyAidokuSourcesStorageKey
                    ),
                    original: metadataStore.originalData.map {
                        ReaderExtensionReconnectTransactionJournal.Value.data($0)
                    } ?? .absent,
                    replacement: legacyReplacement
                ))
            }

            // Order, enabled state and the Discover selection describe a source
            // that has finished moving. Re-applying them on every later partial
            // run would silently undo a manual reorder, re-disable a source the
            // user just enabled, and yank Discover onto a source Settings still
            // lists as pending.
            guard !retainsLegacySource else { continue }

            if metadataStore.selectedHomeSourceID == "aidoku:\(legacySourceID)" {
                result.append(PlannedMutation(
                    target: .metadata(
                        store: metadataStore.store,
                        key: selectedHomeSourceKey,
                        label: metadataStore.label
                    ),
                    journalLocation: .metadataDefaults(
                        scope: metadataStore.journalScope,
                        key: selectedHomeSourceKey
                    ),
                    original: metadataStore.selectedHomeSourceID.map {
                        ReaderExtensionReconnectTransactionJournal.Value.string($0)
                    } ?? .absent,
                    replacement: .string(
                        "readerExtension:\(installedSource.id.rawValue)"
                    )
                ))
            }

            if metadataStore.installedSources.contains(where: {
                $0.id == installedSource.id
            }) {
                let replacement = try installedSourcesData(
                    metadataStore.installedSources,
                    applying: legacySource,
                    to: installedSource.id
                )
                result.append(PlannedMutation(
                    target: .metadata(
                        store: metadataStore.store,
                        key: ReaderExtensionPersistence.installedSourcesKey,
                        label: metadataStore.label
                    ),
                    journalLocation: .metadataDefaults(
                        scope: metadataStore.journalScope,
                        key: ReaderExtensionPersistence.installedSourcesKey
                    ),
                    original: metadataStore.originalInstalledSourcesData.map {
                        ReaderExtensionReconnectTransactionJournal.Value.data($0)
                    } ?? .absent,
                    replacement: .data(replacement)
                ))
            }
        }

        guard !result.isEmpty,
              Set(result.map(\.journalLocation)).count == result.count else {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                "Reader reconnect transaction"
            )
        }
        return result
    }

    private static func mutationLabel(_ target: PlannedMutationTarget) -> String {
        switch target {
        case .route(let location): return location.label
        case .metadata(_, _, let label): return label
        }
    }

    private static func currentValue(
        for target: PlannedMutationTarget
    ) throws -> ReaderExtensionReconnectTransactionJournal.Value {
        switch target {
        case .route(let location):
            return try read(location).map {
                ReaderExtensionReconnectTransactionJournal.Value.data($0)
            } ?? .absent
        case .metadata(let store, let key, let label):
            let value = store.object(forKey: key)
            if value == nil { return .absent }
            if let data = value as? Data { return .data(data) }
            if let string = value as? String { return .string(string) }
            throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
        }
    }

    private static func applyValue(
        _ value: ReaderExtensionReconnectTransactionJournal.Value,
        to target: PlannedMutationTarget
    ) throws {
        switch target {
        case .route(let location):
            switch value {
            case .data(let data):
                try write(data, to: location)
            case .absent:
                switch location {
                case .defaults(let key, _):
                    UserDefaults.standard.removeObject(forKey: key)
                    try synchronize(
                        UserDefaults.standard,
                        label: location.label
                    )
                case .file(let url, _):
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        try ReaderExtensionReconnectTransactionJournal.synchronizeDirectory(
                            url.deletingLastPathComponent()
                        )
                    }
                }
            case .string:
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    location.label
                )
            }
        case .metadata(let store, let key, let label):
            switch value {
            case .absent: store.removeObject(forKey: key)
            case .data(let data): store.set(data, forKey: key)
            case .string(let string): store.set(string, forKey: key)
            }
            try synchronize(store, label: label)
            guard try currentValue(for: target) == value else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(label)
            }
        }
    }

    private static func synchronize(_ store: UserDefaults, label: String) throws {
        guard store.synchronize() else {
            throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(label)
        }
    }

    private static func journalTargets(
        servicesStore: UserDefaults
    ) throws -> [ReaderExtensionReconnectTransactionJournal.Location: PlannedMutationTarget] {
        var targets: [ReaderExtensionReconnectTransactionJournal.Location: PlannedMutationTarget] = [:]
        for location in try storeLocations() {
            let journalLocation: ReaderExtensionReconnectTransactionJournal.Location
            switch location {
            case .defaults(let key, _):
                journalLocation = .standardDefaults(key: key)
            case .file(let url, _):
                journalLocation = .file(path: url.standardizedFileURL.path)
            }
            targets[journalLocation] = .route(location)
        }
        let allowedKeys = [
            BackupReaderExtensionState.legacyAidokuSourcesStorageKey,
            selectedHomeSourceKey,
            ReaderExtensionPersistence.installedSourcesKey
        ]
        var metadataStores: [(scope: String, store: UserDefaults)] = [
            (metadataScopeStandard, .standard),
            (metadataScopePrimary, servicesStore)
        ]
        if ProfileManager.shared.rosterStoreIsReadable {
            metadataStores.append(contentsOf: ProfileManager.shared.profiles.map {
                (
                    metadataScopeProfilePrefix + $0.id.uuidString,
                    ProfileSettingsStore.shared.store(for: $0.id)
                )
            })
        }
        for metadata in metadataStores {
            for key in allowedKeys {
                targets[.metadataDefaults(scope: metadata.scope, key: key)] = .metadata(
                    store: metadata.store,
                    key: key,
                    label: "Reader reconnect transaction"
                )
            }
        }
        return targets
    }

    private static func storeLocations() throws -> [StoreLocation] {
        let manager = ProfileManager.shared
        guard manager.rosterStoreIsReadable else {
            throw ReaderExtensionLegacyReconnectError.unreadableProfileRoster
        }
        let profileIDs = Array(
            Set(manager.profiles.map(\.id)).union([ProfileManager.defaultProfileID])
        ).sorted { $0.uuidString < $1.uuidString }

        var locations: [StoreLocation] = [
            .defaults(key: "mangaLibraryCollections", label: "legacy Reader library"),
            .defaults(key: "mangaReadingProgress", label: "legacy Reader progress")
        ]
        for profileID in profileIDs {
            let token = ProfileScopedStorage.token(for: profileID)
            locations.append(
                .defaults(
                    key: MangaLibraryManager.storageKey(for: profileID),
                    label: "Reader library \(token)"
                )
            )
            locations.append(
                .defaults(
                    key: MangaReadingProgressManager.storageKey(for: profileID),
                    label: "Reader progress \(token)"
                )
            )
            locations.append(
                .file(
                    url: UserRatingManager.fileURL(for: profileID),
                    label: "Reader ratings \(token)"
                )
            )
        }

        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        locations.append(
            .file(
                url: documents.appendingPathComponent("UserRatings.json"),
                label: "legacy Reader ratings"
            )
        )
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let downloadRoot = appSupport.appendingPathComponent("KanzenDownloads", isDirectory: true)
        locations.append(
            .file(
                url: downloadRoot.appendingPathComponent(".reader_downloads.json"),
                label: "Reader download index"
            )
        )
        if fileManager.fileExists(atPath: downloadRoot.path) {
            let rootValues = try? downloadRoot.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(
                    "Reader download directory"
                )
            }
            var traversalFailed = false
            guard let enumerator = fileManager.enumerator(
            at: downloadRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in
                traversalFailed = true
                return false
            }
            ) else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(
                    "Reader download directory"
                )
            }
            var manifestCount = 0
            for case let url as URL in enumerator where url.lastPathComponent == "chapter.json" {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                manifestCount += 1
                guard manifestCount <= maximumRouteStoreCount else {
                    throw ReaderExtensionLegacyReconnectError.storeTooLarge(
                        "Reader download manifests"
                    )
                }
                locations.append(
                    .file(url: url, label: "Reader download chapter manifest")
                )
            }
            guard !traversalFailed else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(
                    "Reader download directory"
                )
            }
        }
        return Array(Set(locations)).sorted { $0.label < $1.label }
    }

    private static func read(_ location: StoreLocation) throws -> Data? {
        switch location {
        case .defaults(let key, let label):
            let value = UserDefaults.standard.object(forKey: key)
            guard value != nil else { return nil }
            guard let data = value as? Data,
                  !data.isEmpty,
                  data.count <= maximumRouteStoreBytes else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            return data
        case .file(let url, let label):
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  let fileSize = values?.fileSize,
                  fileSize > 0,
                  fileSize <= maximumRouteStoreBytes else {
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard data.count == fileSize else {
                    throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
                }
                return data
            } catch {
                if error is ReaderExtensionLegacyReconnectError { throw error }
                throw ReaderExtensionLegacyReconnectError.unreadableStore(label)
            }
        }
    }

    private static func write(_ data: Data, to location: StoreLocation) throws {
        switch location {
        case .defaults(let key, _):
            UserDefaults.standard.set(data, forKey: key)
            try synchronize(UserDefaults.standard, label: location.label)
            guard UserDefaults.standard.data(forKey: key) == data else {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(
                    location.label
                )
            }
        case .file(let url, let label):
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                try ReaderExtensionReconnectTransactionJournal.synchronizeFileAndDirectory(url)
                guard try Data(contentsOf: url) == data else {
                    throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(label)
                }
            } catch let error as ReaderExtensionLegacyReconnectError {
                throw error
            } catch {
                throw ReaderExtensionLegacyReconnectError.rewriteVerificationFailed(label)
            }
        }
    }

    private static func mergedReferences(
        _ references: [ReaderExtensionLegacyItemReference]
    ) -> [ReaderExtensionLegacyItemReference] {
        var merged: [String: ReaderExtensionLegacyItemReference] = [:]
        for reference in references {
            if let existing = merged[reference.id] {
                merged[reference.id] = ReaderExtensionLegacyItemReference(
                    legacySourceID: reference.legacySourceID,
                    legacyItemKey: reference.legacyItemKey,
                    title: existing.title ?? reference.title,
                    author: existing.author ?? reference.author,
                    coverURL: existing.coverURL ?? reference.coverURL,
                    occurrenceCount: existing.occurrenceCount + reference.occurrenceCount
                )
            } else {
                merged[reference.id] = reference
            }
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    private static func canonicalIdentifier(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func canonicalSourceName(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func canonicalHost(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !value.isEmpty else { return nil }
        while value.hasSuffix(".") { value.removeLast() }
        if value.hasPrefix("www.") { value.removeFirst(4) }
        return value.isEmpty ? nil : value
    }

    private static func canonicalLanguage(_ value: String) -> String? {
        let canonical = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "_", with: "-")
        guard !canonical.isEmpty else { return nil }
        return canonical.split(separator: "-").first.map(String.init)
    }

    private static func markQuarantined(_ error: Error) {
        UserDefaults.standard.set(
            [
                "failedAt": Date().timeIntervalSince1970,
                "reason": String(reflecting: type(of: error))
            ] as [String: Any],
            forKey: quarantineKey
        )
        Logger.shared.log(
            "Reader Extensions: legacy reconnect preflight quarantined an unreadable Reader store; cleanup is deferred",
            type: "Storage"
        )
    }

    @MainActor
    private static func reloadLiveReaderStores() {
        _ = try? ReaderExtensionManager.shared.reloadPersistedStateAfterRestore()
        let manager = ProfileManager.shared
        guard manager.rosterStoreIsReadable else { return }
        for profile in manager.profiles {
            if let collections = MangaLibraryManager.shared.collectionsSnapshot(
                forProfile: profile.id
            ) {
                MangaLibraryManager.shared.applyRestoredCollections(
                    collections,
                    forProfile: profile.id
                )
            }
            if let progress = MangaReadingProgressManager.shared.progressSnapshot(
                forProfile: profile.id
            ) {
                MangaReadingProgressManager.shared.applyRestoredProgress(
                    progress,
                    forProfile: profile.id
                )
            }
        }
        NotificationCenter.default.post(
            name: .readerExtensionLegacyRoutesDidReconnect,
            object: nil
        )
    }
}

extension Notification.Name {
    static let readerExtensionLegacyRoutesDidReconnect = Notification.Name(
        "readerExtensionLegacyRoutesDidReconnect"
    )
}

/// One-shot, profile-aware conversion of the old Aidoku metadata store. It never opens an
/// `.aix`, restores a package archive, contacts a legacy list URL, or executes old source code.
enum ReaderExtensionAidokuMigration {
    static let completionKey = "readerExtensions.aidokuMigrationComplete.v1"
    static let quarantineKey = "readerExtensions.aidokuMigrationQuarantine.v1"

    private static let legacyKeys = [
        "kanzenAidokuSourceLists",
        "kanzenAidokuInstalledSources",
        "kanzenAidokuShowMatureSources",
        "kanzenAidokuAutoUpdateSources",
        "kanzenAidokuLastAutoUpdate",
        "kanzenAidokuPendingPackageRepairIDs"
    ]

    private static let transactionKeys = [
        ReaderExtensionPersistence.repositoriesKey,
        ReaderExtensionPersistence.installedSourcesKey,
        ReaderExtensionPersistence.showMatureSourcesKey,
        ReaderExtensionPersistence.autoUpdateSourcesKey,
        ReaderExtensionPersistence.lastAutoUpdateKey,
        BackupReaderExtensionState.legacyAidokuSourcesStorageKey,
        completionKey,
        quarantineKey
    ] + legacyKeys

    private enum MigrationError: LocalizedError {
        case unreadableLegacyMetadata
        case unsafeLegacyMetadata
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .unreadableLegacyMetadata:
                return "Legacy Reader source metadata is unreadable."
            case .unsafeLegacyMetadata:
                return "Legacy Reader source metadata failed validation."
            case .verificationFailed:
                return "Legacy Reader source migration did not verify."
            }
        }
    }

    private struct PersistedAidokuSource: Decodable {
        let id: String
        let name: String
        let version: Int
        let languages: [String]
        let externalIconURL: String?
        let contentRatingRawValue: Int
        let sourceListURL: String?
        let packageURL: String?
        let isEnabled: Bool
        let order: Int
        let lastUpdated: Date?
        let packageDigest: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, version, languages, externalIconURL, contentRatingRawValue
            case sourceListURL, packageURL, isEnabled, order, lastUpdated, packageDigest
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try BackupAidokuLegacyWirePolicy.sourceID(
                container.decode(String.self, forKey: .id),
                codingPath: container.codingPath + [CodingKeys.id]
            )
            if let decodedName = try container.decodeIfPresent(String.self, forKey: .name) {
                name = try BackupAidokuLegacyWirePolicy.requiredString(
                    decodedName,
                    maximumBytes: BackupAidokuLegacyWirePolicy.maximumNameBytes,
                    field: "name",
                    codingPath: container.codingPath + [CodingKeys.name]
                )
            } else {
                name = id
            }
            let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
            guard (0...Int(Int32.max)).contains(decodedVersion) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "Legacy Reader source version is invalid."
                )
            }
            version = decodedVersion
            languages = try container.decodeIfPresent(
                BackupAidokuBoundedLanguages.self,
                forKey: .languages
            )?.values ?? []
            externalIconURL = try BackupAidokuLegacyWirePolicy.optionalString(
                container.decodeIfPresent(String.self, forKey: .externalIconURL),
                maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
                field: "external icon URL",
                codingPath: container.codingPath + [CodingKeys.externalIconURL]
            )
            let decodedRating = try container.decodeIfPresent(
                Int.self,
                forKey: .contentRatingRawValue
            ) ?? 0
            guard (0...3).contains(decodedRating) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .contentRatingRawValue,
                    in: container,
                    debugDescription: "Legacy Reader source content rating is invalid."
                )
            }
            contentRatingRawValue = decodedRating
            sourceListURL = try BackupAidokuLegacyWirePolicy.optionalString(
                container.decodeIfPresent(String.self, forKey: .sourceListURL),
                maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
                field: "source-list URL",
                codingPath: container.codingPath + [CodingKeys.sourceListURL]
            )
            packageURL = try BackupAidokuLegacyWirePolicy.optionalString(
                container.decodeIfPresent(String.self, forKey: .packageURL),
                maximumBytes: BackupAidokuLegacyWirePolicy.maximumURLBytes,
                field: "package URL",
                codingPath: container.codingPath + [CodingKeys.packageURL]
            )
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
            let decodedOrder = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0Û8é¼­zÊ&ŠÛ^u[œÚ[ÛœÎˆYØXŞH™XY\ˆ[\Ü˜\K\XÚØYÙHÛX[\Ú[™]H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆCBˆYˆ™[[İ™YÛİ[ˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™XY\ˆ^[œÚ[ÛœÎˆ™[[İ™Y
™[[İ™YÛİ[
H™\šYšYYYØXŞHXÚØYÙKØØXÚHØØ][ÛŠÊH‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆCBŸCBˆÙ[™YƒBƒBœİXİ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[ˆÛÙX›K\]X]X›HÃBˆİ]XÈ]X^[][QÛXZ[”™XÛÜ™Ûİ[HLÌÌBƒBˆ]Xœ˜\R][\Îˆ[Bˆ][İšYT›ÙÜ™\ÜÎˆ[Bˆ]\\ÛÙT›ÙÜ™\ÜÎˆ[Bˆ]X[™ØSXœ˜\R][\Îˆ[Bˆ]X[™ØT™XY[™Ô›ÙÜ™\ÜÎˆ[Bˆ]\Ù\”˜][™ÜÎˆ[Bˆ]Ù\šXÙ\Îˆ[Bˆ]İ™[Z[ĞYÛœÎˆ[Bˆ]ÚŞTİ™X[TÛİ\˜Ù\Îˆ[Bˆ]Ø[™[“[Ù[\Îˆ[Bˆ]ZYÚİTÛİ\˜Ù\Îˆ[Bˆ]ÛÛ[YÙ\İˆİš[™ÏÃBˆ]ÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]Nˆİš[™ÏÃBƒBˆ[š]
Û˜\Úİˆ˜XÚİ\]K[˜ÛÙY]Nˆ]JHÃBˆXœ˜\R][\ÈHÙ[‹˜›İ[™Yİ[JÛ˜\Úİ˜ÛÛXİ[ÛœË›X\È	š][\Ë˜Ûİ[JCBˆ[İšYT›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
Û˜\Úİœ›ÙÜ™\ÜÑ]K›[İšYT›ÙÜ™\ÜË˜Ûİ[
CBˆ\\ÛÙT›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
Û˜\Úİœ›ÙÜ™\ÜÑ]K™\\ÛÙT›ÙÜ™\ÜË˜Ûİ[
CBˆX[™ØSXœ˜\R][\ÈHÙ[‹˜›İ[™Yİ[JÛ˜\Úİ›X[™ØPÛÛXİ[ÛœË›X\È	š][\Ë˜Ûİ[JCBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
Û˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜË˜Ûİ[
CBˆ\Ù\”˜][™ÜÈHÙ[‹˜›İ[™YÛİ[
Û˜\Úİ\Ù\”˜][™ÜË˜Ûİ[
CBˆÙ\šXÙ\ÈHÙ[‹˜›İ[™YÛİ[
Û˜\ÚİœÙ\šXÙ\Ë˜Ûİ[
CBˆİ™[Z[ĞYÛœÈHÙ[‹˜›İ[™YÛİ[
Û˜\Úİœİ™[Z[ĞYÛœÏË˜Ûİ[ÏÈ
CBˆÚŞTİ™X[TÛİ\˜Ù\ÈHÙ[‹˜›İ[™Yİ[JÃBˆÛ˜\ÚİœÚŞTİ™X[OËœ™\ÜÚ]ÜšY\Ë˜Ûİ[ÏÈBˆÛ˜\ÚİœÚŞTİ™X[OËœYÚ[œË˜Ûİ[ÏÈBˆJCBˆØ[™[“[Ù[\ÈHÙ[‹˜›İ[™YÛİ[
Û˜\ÚİšØ[™[“[Ù[\Ë˜Ûİ[
CBˆËÈÙY\H[˜ÛÙYšY[˜[YH›ÜˆÛİY\ØÚ[XHÛÛ\]Xš[]HÚ[HÛİ[[™ÈCBˆËÈ™\XÙ[Y[™XY\ˆ^[œÚ[ÛœÈÛXZ[ˆ
[˜ÛY[™È[œ™\ÛÛ™YYØXŞH™XÛÛ›™Xİ›İÜÊKƒBˆZYÚİTÛİ\˜Ù\ÈHÙ[‹˜›İ[™YÛİ[
BˆÛ˜\Úİœ™XY\‘^[œÚ[ÛœÔİ]OËœÛİ\˜ÙPÛİ[›ÜÛÛ\]Xš[]CBˆÏÈÛ˜\Úİ˜ZYÚİTİ]OËš[œİ[YÛİ\˜Ù\Ë˜Ûİ[BˆÏÈBˆ
CBˆ]YÙ\İÈHÙ[‹œİX›PÛÛ[YÙ\İÊ›Üˆ[˜ÛÙY]JCBˆÛÛ[YÙ\İHYÙ\İË™[BˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]HHYÙ\İË™^ÛY[™ĞÛİYÚ]YYXTİ]CBˆCBƒBˆ˜\ˆYX[š[™Ù[™XÛÜ™Ûİ[ˆ[ÃBˆÙ[‹œØY™Tİ[JÛİ[ÊCBˆCBƒBˆ[˜È\Ôİ\ÜXÚ[İ\Ô™YXİ[ÛŠœ›ÛH™]š[İ\ÎˆÙ[ŠHOˆ›ÛÛÃBˆš\
™]š[İ\Ë˜Ûİ[ËÛİ[ÊK˜ÛÛZ[œÈÈÛÛİ[™]ĞÛİ[[ƒBˆİX\™™]ĞÛİ[ÛÛİ[[ÙHÈ™]\›ˆ˜[ÙHCBˆYˆ™]ĞÛİ[OHÈ™]\›ˆYHCBˆ]™[[İ™YHÛÛİ[H™]ĞÛİ[Bˆ]XZ›Üš]U™\ÚÛHÛÛİ[Èˆ
ÈÛÛİ[	HƒBˆ™]\›ˆ™[[İ™YHÈ	‰ˆ™[[İ™YHXZ›Üš]U™\ÚÛBˆCBˆCBƒBˆ[˜È\ÓYX[š[™Ù[S[Ü™Q]J[ˆİ\ˆÙ[ŠHOˆ›ÛÛÃBˆİ\‹š\Ôİ\ÜXÚ[İ\Ô™YXİ[ÛŠœ›ÛNˆÙ[ŠCBˆCBƒBˆ[˜È\Ğ[S[Ü™Q]J[ˆİ\ˆÙ[ŠHOˆ›ÛÛÃBˆš\
Ûİ[Ëİ\‹˜Ûİ[ÊK˜ÛÛZ[œÈÈİ\œ™[Ûİ[İ\Ûİ[[ƒBˆİ\œ™[Ûİ[ˆİ\Ûİ[BˆCBˆCBƒBˆ[˜È\ÑY™™\™[ÛÛ[
[ˆİ\ˆÙ[ŠHOˆ›ÛÛÃBˆYˆ]ÛÛ[YÙ\İ]İ\‘YÙ\İHİ\‹˜ÛÛ[YÙ\İÃBˆ™]\›ˆÛÛ[YÙ\İOHİ\‘YÙ\İBˆCBˆ™]\›ˆÛİ[ÈOHİ\‹˜Ûİ[ÃBˆCBƒBˆ[˜È^ÛY[™ĞÛİYÚ]YYXTİ]J
HOˆÙ[ˆÃBˆÙ[ŠBˆXœ˜\R][\ÎˆBˆ[İšYT›ÙÜ™\ÜÎˆBˆ\\ÛÙT›ÙÜ™\ÜÎˆBˆX[™ØSXœ˜\R][\ÎˆX[™ØSXœ˜\R][\ËBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÎˆX[™ØT™XY[™Ô›ÙÜ™\ÜËBˆ\Ù\”˜][™ÜÎˆBˆÙ\šXÙ\ÎˆÙ\šXÙ\ËBˆİ™[Z[ĞYÛœÎˆİ™[Z[ĞYÛœËBˆÚŞTİ™X[TÛİ\˜Ù\ÎˆÚŞTİ™X[TÛİ\˜Ù\ËBˆØ[™[“[Ù[\ÎˆØ[™[“[Ù[\ËBˆZYÚİTÛİ\˜Ù\ÎˆZYÚİTÛİ\˜Ù\ËBˆÛÛ[YÙ\İˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]KBˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]NˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]CBˆ
CBˆCBƒBˆ[š]
BˆXœ˜\R][\Îˆ[Bˆ[İšYT›ÙÜ™\ÜÎˆ[Bˆ\\ÛÙT›ÙÜ™\ÜÎˆ[BˆX[™ØSXœ˜\R][\Îˆ[BˆX[™ØT™XY[™Ô›ÙÜ™\ÜÎˆ[Bˆ\Ù\”˜][™ÜÎˆ[BˆÙ\šXÙ\Îˆ[Bˆİ™[Z[ĞYÛœÎˆ[BˆÚŞTİ™X[TÛİ\˜Ù\Îˆ[BˆØ[™[“[Ù[\Îˆ[BˆZYÚİTÛİ\˜Ù\Îˆ[BˆÛÛ[YÙ\İˆİš[™ÏËBˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]Nˆİš[™ÏÃBˆ
HÃBˆÙ[‹›Xœ˜\R][\ÈHÙ[‹˜›İ[™YÛİ[
Xœ˜\R][\ÊCBˆÙ[‹›[İšYT›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
[İšYT›ÙÜ™\ÜÊCBˆÙ[‹™\\ÛÙT›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
\\ÛÙT›ÙÜ™\ÜÊCBˆÙ[‹›X[™ØSXœ˜\R][\ÈHÙ[‹˜›İ[™YÛİ[
X[™ØSXœ˜\R][\ÊCBˆÙ[‹›X[™ØT™XY[™Ô›ÙÜ™\ÜÈHÙ[‹˜›İ[™YÛİ[
X[™ØT™XY[™Ô›ÙÜ™\ÜÊCBˆÙ[‹\Ù\”˜][™ÜÈHÙ[‹˜›İ[™YÛİ[
\Ù\”˜][™ÜÊCBˆÙ[‹œÙ\šXÙ\ÈHÙ[‹˜›İ[™YÛİ[
Ù\šXÙ\ÊCBˆÙ[‹œİ™[Z[ĞYÛœÈHÙ[‹˜›İ[™YÛİ[
İ™[Z[ĞYÛœÊCBˆÙ[‹œÚŞTİ™X[TÛİ\˜Ù\ÈHÙ[‹˜›İ[™YÛİ[
ÚŞTİ™X[TÛİ\˜Ù\ÊCBˆÙ[‹šØ[™[“[Ù[\ÈHÙ[‹˜›İ[™YÛİ[
Ø[™[“[Ù[\ÊCBˆÙ[‹˜ZYÚİTÛİ\˜Ù\ÈHÙ[‹˜›İ[™YÛİ[
ZYÚİTÛİ\˜Ù\ÊCBˆÙ[‹˜ÛÛ[YÙ\İHÛÛ[YÙ\İBˆÙ[‹˜ÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]HHÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]CBˆCBƒBˆš]˜]H[[HÛÙ[™ÒÙ^\Îˆİš[™ËÛÙ[™ÒÙ^HÃBˆØ\ÙHXœ˜\R][\Ë[İšYT›ÙÜ™\ÜË\\ÛÙT›ÙÜ™\ÜËX[™ØSXœ˜\R][\ÃBˆØ\ÙHX[™ØT™XY[™Ô›ÙÜ™\ÜË\Ù\”˜][™ÜËÙ\šXÙ\Ëİ™[Z[ĞYÛœÃBˆØ\ÙHÚŞTİ™X[TÛİ\˜Ù\ËØ[™[“[Ù[\ËZYÚİTÛİ\˜Ù\ËÛÛ[YÙ\İBˆØ\ÙHÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]CBˆCBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ]ÛÛZ[™\ˆHHXÛÙ\‹˜ÛÛZ[™\ŠÙ^YYNˆÛÙ[™ÒÙ^\ËœÙ[ŠCBˆXœ˜\R][\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ›Xœ˜\R][\ÊCBˆ[İšYT›ÙÜ™\ÜÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ›[İšYT›ÙÜ™\ÜÊCBˆ\\ÛÙT›ÙÜ™\ÜÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ™\\ÛÙT›ÙÜ™\ÜÊCBˆX[™ØSXœ˜\R][\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ›X[™ØSXœ˜\R][\ÊCBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ›X[™ØT™XY[™Ô›ÙÜ™\ÜÊCBˆ\Ù\”˜][™ÜÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ\Ù\”˜][™ÜÊCBˆÙ\šXÙ\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^NˆœÙ\šXÙ\ÊCBˆİ™[Z[ĞYÛœÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆœİ™[Z[ĞYÛœÊCBˆÚŞTİ™X[TÛİ\˜Ù\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^NˆœÚŞTİ™X[TÛİ\˜Ù\ÊCBˆØ[™[“[Ù[\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^NˆšØ[™[“[Ù[\ÊCBˆZYÚİTÛİ\˜Ù\ÈHHÙ[‹™XÛÙPÛİ[
œ›ÛNˆÛÛZ[™\‹›Ü’Ù^Nˆ˜ZYÚİTÛİ\˜Ù\ÊCBˆÛÛ[YÙ\İHHÛÛZ[™\‹™XÛÙRY”™\Ù[
İš[™ËœÙ[‹›Ü’Ù^Nˆ˜ÛÛ[YÙ\İ
CBˆÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]HHHÛÛZ[™\‹™XÛÙRY”™\Ù[
Bˆİš[™ËœÙ[‹Bˆ›Ü’Ù^Nˆ˜ÛÛ[YÙ\İ^ÛY[™ĞÛİYÚ]YYXTİ]CBˆ
CBˆCBƒBˆš]˜]H˜\ˆÛİ[ÎˆÒ[HÃBˆÃBˆXœ˜\R][\ËBˆ[İšYT›ÙÜ™\ÜËBˆ\\ÛÙT›ÙÜ™\ÜËBˆX[™ØSXœ˜\R][\ËBˆX[™ØT™XY[™Ô›ÙÜ™\ÜËBˆ\Ù\”˜][™ÜËBˆÙ\šXÙ\ËBˆİ™[Z[ĞYÛœËBˆÚŞTİ™X[TÛİ\˜Ù\ËBˆØ[™[“[Ù[\ËBˆZYÚİTÛİ\˜Ù\ÃBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈXÛÙPÛİ[
Bˆœ›ÛHÛÛZ[™\ˆÙ^YYXÛÙ[™ĞÛÛZ[™\ÛÙ[™ÒÙ^\Ï‹Bˆ›Ü’Ù^HÙ^NˆÛÙ[™ÒÙ^\ÃBˆ
H›İÜÈOˆ[ÃBˆ]˜[YHHHÛÛZ[™\‹™XÛÙRY”™\Ù[
[œÙ[‹›Ü’Ù^NˆÙ^JHÏÈBˆİX\™
‹‹›X^[][QÛXZ[”™XÛÜ™Ûİ[
K˜ÛÛZ[œÊ˜[YJH[ÙHÃBˆ›İÈXÛÙ[™Ñ\œ›Ü‹™]PÛÜœ\Y\œ›ÜŠBˆ›Ü’Ù^NˆÙ^KBˆ[ˆÛÛZ[™\‹BˆXYÑ\ØÜš\[Ûˆ”Û˜\Úİ›Ûİš[Ûİ[\È™YØ]]™HÜˆ^ÙYYÈ]È›İ[™ˆƒBˆ
CBˆCBˆ™]\›ˆ˜[YCBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™YÛİ[
È˜[YNˆ[
HOˆ[ÃBˆZ[ŠX^
˜[YJKX^[][QÛXZ[”™XÛÜ™Ûİ[
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™Yİ[JÈ˜[Y\ÎˆÒ[JHOˆ[ÃBˆZ[ŠØY™Tİ[J˜[Y\ÊKX^[][QÛXZ[”™XÛÜ™Ûİ[
CBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØY™Tİ[JÈ˜[Y\ÎˆÒ[JHOˆ[ÃBˆ˜[Y\Ëœ™YXÙJ[Îˆ
HÈİ[˜[YH[ƒBˆ]›Û›™YØ]]™HHX^
˜[YJCBˆ]
İ[Kİ™\™›İÊHHİ[˜Y[™Ô™\Ü[™Óİ™\™›İÊ›Û›™YØ]]™JCBˆİ[Hİ™\™›İÈÈ[›X^ˆİ[CBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈİX›PÛÛ[YÙ\İÊBˆ›Üˆ]Nˆ]CBˆ
HOˆ
[ˆİš[™ÏË^ÛY[™ĞÛİYÚ]YYXTİ]Nˆİš[™ÏÊHÃBˆÚYˆØ[’[\Ü
Ü\ÒÚ]
CBˆİX\™˜\ˆØš™XİHOÈ”ÓÓ”Ù\šX[^˜][Û‹šœÛÛ“Øš™Xİ
Ú]ˆ]JH\ÏÈÔİš[™Îˆ[WH[ÙHÃBˆ™]\›ˆ
š[š[
CBˆCBƒBˆØš™Xİœ™[[İ™U˜[YJ›Ü’Ù^Nˆ˜Ü™X]Y]HŠCBˆØš™Xİœ™[[İ™U˜[YJ›Ü’Ù^Nˆ™\œÚ[ÛˆŠCBˆÃBˆ™Ú]X”™[X\ÙU\]P]˜Z[X›H‹Bˆ™Ú]X”™[X\ÙS]\İ™\œÚ[Ûˆ‹Bˆ™Ú]X”™[X\ÙUT“‹Bˆ™Ú]X”™[X\ÙTÚİĞ[\[™[™È‹Bˆ™Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[Ûˆ‹Bˆ›ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈ‹Bˆ›ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈƒBˆK™›Ü‘XXÚÈØš™Xİœ™[[İ™U˜[YJ›Ü’Ù^Nˆ	
HCBˆYˆ˜\ˆÚŞTİ™X[HHØš™XİÈœÚŞTİ™X[H—H\ÏÈÔİš[™Îˆ[WHÃBˆÚŞTİ™X[Kœ™[[İ™U˜[YJ›Ü’Ù^Nˆ˜Ü™X]Y]ŠCBˆØš™XİÈœÚŞTİ™X[H—HHÚŞTİ™X[CBˆCBˆØš™XİHØÜX•˜[œÚY[ÛİYY]Y]JØš™Xİ
H\ÏÈÔİš[™Îˆ[WHÏÈØš™XİBˆİX\™]›Ü›X[^™Y]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™XİˆØš™XİÜ[ÛœÎˆËœÛÜYÙ^\×JH[ÙHÃBˆ™]\›ˆ
š[š[
CBˆCBˆ][HÒLM‹š\Ú
]Nˆ›Ü›X[^™Y]JCBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆÚYˆP•QÃBˆYˆ›ØÙ\ÜÒ[™›Ëœ›ØÙ\ÜÒ[™›Ë™[š\›Û›Y[È‘PÓTÑWÑP•Q×ÑQÑTÕÑST—HOHŒH‹Bˆ]Øİ[Y[ÈHš[SX[˜YÙ\‹™Y˜][\›Ê›Üˆ™Øİ[Y[\™XİÜK[ˆ\Ù\‘ÛXZ[“X\ÚÊK™š\œİÃBˆ]İ[\H[
]J
K[YR[\˜[Ú[˜ÙLNMÌ
ˆL
CBˆOÈ›Ü›X[^™Y]KÜš]JBˆÎˆØİ[Y[Ë˜\[™[™Ô]ÛÛ\Û™[
™YÙ\İY[\W
İ[\
KW
İš[™Ê[œ™Yš^

JJKšœÛÛˆŠCBˆ
CBˆCBˆÙ[™YƒBˆ˜\ˆ^ÛY[™ÓYYXTİ]HHØš™XİBˆÃBˆ˜ÛÛXİ[ÛœÈ‹Bˆœ›ÙÜ™\ÜÑ]H‹Bˆ\Ù\”˜][™ÜÈ‹Bˆ\Ù\”˜][™Ó›İ\È‹Bˆ˜Ø][ÙÜÈ‹Bˆ›YYXTİ]TÙ][™ÜÈƒBˆK™›Ü‘XXÚÈ^ÛY[™ÓYYXTİ]Kœ™[[İ™U˜[YJ›Ü’Ù^Nˆ	
HCBˆYˆ]›Ùš[\ÈH^ÛY[™ÓYYXTİ]VÈœ›Ùš[\È—H\ÏÈÖÔİš[™Îˆ[WWHÃBˆ]Ø[›ÛšXØ[›Ùš[RÙ^\ÎˆÙ]İš[™ÏˆHÃBƒBˆ›˜[YH‹˜]˜]\”Ş[X›Û‹˜]˜]\ÛÛÜ’^‹˜]˜]\”İÑ]H‹Bˆš\ÒÚYÔ›Ùš[H‹˜Ü™X]Y]‹œ[’\Ú‹œ[Ú[™ÙY]‹BˆšÚYÑ›YĞÚ[™ÙY]‹BƒBˆ˜ÛÛXİ[ÛœÈ‹œ›ÙÜ™\ÜÑ]H‹˜Ø][ÙÜÈ‹\Ù\”˜][™ÜÈ‹Bˆ\Ù\”˜][™Ó›İ\È‹œ›ÙÜ™\ÜÕØ\ĞØ\\™Y‹Bˆœ˜][™ÜÕÙ\™PØ\\™Y‹˜ÛÛXİ[ÛœÕÙ\™PØ\\™Y‹Bˆ˜Ø][ÙÜÕÙ\™PØ\\™YƒBˆCBˆ^ÛY[™ÓYYXTİ]VÈœ›Ùš[\È—HH›Ùš[\Ë›X\È›Ùš[H[ƒBˆ˜\ˆÛİ\˜ÙP[™™XY\“Û›HH›Ùš[K™š[\ˆÃBˆXØ[›ÛšXØ[›Ùš[RÙ^\Ë˜ÛÛZ[œÊ	šÙ^JCBˆCBˆYˆ˜\ˆÙ][™ÜÈHÛİ\˜ÙP[™™XY\“Û›VÈœÙ][™ÜÈ—H\ÏÈÔİš[™Îˆ[WHÃBˆ›ÜˆÙ^H[ˆ\œ˜^JÙ][™ÜËšÙ^\ÊCBˆÚ\™HYYXTİ]TÙ][™Ô™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHš[ÃBˆÙ][™ÜËœ™[[İ™U˜[YJ›Ü’Ù^NˆÙ^JCBˆCBˆÛİ\˜ÙP[™™XY\“Û›VÈœÙ][™ÜÈ—HHÙ][™ÜÃBˆCBˆ™]\›ˆÛİ\˜ÙP[™™XY\“Û›CBˆCBˆCBˆİX\™]YYXR[™\[™[]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JBˆÚ]”ÓÓ“Øš™Xİˆ^ÛY[™ÓYYXTİ]KBˆÜ[ÛœÎˆËœÛÜYÙ^\×CBˆ
H[ÙHÃBˆ™]\›ˆ
[š[
CBˆCBˆ]^ÛY[™ÈHÒLM‹š\Ú
]NˆYYXR[™\[™[]JCBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆ™]\›ˆ
[^ÛY[™ÊCBˆÙ[ÙCBˆ™]\›ˆ
š[š[
CBˆÙ[™YƒBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØÜX•˜[œÚY[ÛİYY]Y]JÈ˜[YNˆ[JHOˆ[HÃBˆ]˜[œÚY[Ù^\ÎˆÙ]İš[™ÏˆHÃBˆ˜Ü™X]Y]‹›\İ™Yœ™\Ú‹›\İ™Yœ™\ÚY]‹›\İ\œ›Üˆ‹›\İ\]Y‹Bˆš[œİ[Y]‹\]Y]‹œ[›™Y]‹™]˜[X]Y]‹Bˆ›\İ]]Õ\]H‹™]XİY]‹›\İÛİ\˜ÙT™Yœ™\Ú‹œÛİ\˜ÙT™Yœ™\Ú\œ›ÜˆƒBˆCBˆ][X™YY”ÓÓ›Ø’Ù^\ÎˆÙ]İš[™ÏˆHÈ›Y]Y]R”ÓÓˆ—CBˆ][›Ü™\™Yİš[™ÔÙ]Ù^\ÎˆÙ]İš[™ÏˆHÃBˆœ[[YPØ\Xš[]Y\È‹œÙXÜ™]™Y™\™[˜ÙRÙ^\È‹™XÛ\™YÛXZ[œÈ‹\Ù\\›İ™YÛXZ[œÈƒBˆCBˆYˆ]Xİ[Û˜\HH˜[YH\ÏÈÔİš[™Îˆ[WHÃBˆ™]\›ˆXİ[Û˜\Kœ™YXÙJ[ÎˆÔİš[™Îˆ[WJ
JHÈ™\İ[[H[ƒBˆİX\™]˜[œÚY[Ù^\Ë˜ÛÛZ[œÊ[KšÙ^JH[ÙHÈ™]\›ˆCBˆYˆ[X™YY”ÓÓ›Ø’Ù^\Ë˜ÛÛZ[œÊ[KšÙ^JKBˆ]›Ü›X[^™YH›Ü›X[^™Y[X™YY”ÓÓ›Ø‘›Ü‘YÙ\İ
[K˜[YJHÃBˆ™\İ[Ù[KšÙ^WHH›Ü›X[^™YBˆ™]\›ƒBˆCBˆYˆ[›Ü™\™Yİš[™ÔÙ]Ù^\Ë˜ÛÛZ[œÊ[KšÙ^JKBˆ]İš[™ÜÈH[K˜[YH\ÏÈÔİš[™×HÃBˆ™\İ[Ù[KšÙ^WHHİš[™ÜËœÛÜY

CBˆ™]\›ƒBˆCBˆ™\İ[Ù[KšÙ^WHHØÜX•˜[œÚY[ÛİYY]Y]J[K˜[YJCBˆCBˆCBˆYˆ]\œ˜^HH˜[YH\ÏÈĞ[WHÃBˆ™]\›ˆ\œ˜^K›X\
ØÜX•˜[œÚY[ÛİYY]Y]JCBˆCBˆ™]\›ˆ˜[YCBˆCBƒBˆš]˜]Hİ]XÈ[˜È›Ü›X[^™Y[X™YY”ÓÓ›Ø‘›Ü‘YÙ\İ
È˜[YNˆ[JHOˆİš[™ÏÈÃBˆİX\™]˜\ÙMH˜[YH\ÏÈİš[™ËBˆ]]HH]J˜\ÙM[˜ÛÙYˆ˜\ÙM
KBˆ]XÛÙYHOÈ”ÓÓ”Ù\šX[^˜][Û‹šœÛÛ“Øš™Xİ
Ú]ˆ]JH[ÙHÃBˆ™]\›ˆš[BˆCBˆ]ØÜX˜™YHØÜX•˜[œÚY[ÛİYY]Y]JXÛÙY
CBˆİX\™”ÓÓ”Ù\šX[^˜][Û‹š\Õ˜[Y”ÓÓ“Øš™Xİ
ØÜX˜™Y
KBˆ]Ø[›ÛšXØ[HOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JBˆÚ]”ÓÓ“Øš™XİˆØÜX˜™YBˆÜ[ÛœÎˆËœÛÜYÙ^\×CBˆ
H[ÙHÃBˆ™]\›ˆš[BˆCBˆ™]\›ˆİš[™ÊXÛÙ[™ÎˆØ[›ÛšXØ[\ÎˆUœÙ[ŠCBˆCBŸCBƒBœİXİ^\š[Y[[ÛİYÛ˜\Úİˆ[˜ÚXÚÙYÙ[™X›HÃBˆ]]Nˆ]CBˆ]›Ûİš[ˆ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[BŸCBƒBœİXİ^\š[Y[[ÛİY™\İÜ™T™\İ[ˆÙ[™X›HÃBˆ]]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆÙ]URQƒBŸCBƒBˆÚYˆ[ÜÊ“ÔÊCB™[[H™XY\‘^[œÚ[Û”™\İÜ™T™[ØYÛXŞHÃBˆİ]XÈ[˜È™\İÜ™Tİ\š]™\ÊÈ\œ›Üˆ\œ›ÜŠHOˆ›ÛÛÃBˆİX\™]™XY\‘\œ›ÜˆH\œ›Üˆ\ÏÈ™XY\‘^[œÚ[Û‘\œ›Üˆ[ÙHÈ™]\›ˆ˜[ÙHCBˆ™]\›ˆ™XY\‘\œ›ÜˆOHœ[[YU[˜]˜Z[X›CBˆCBŸCBˆÙ[™YƒBƒB™[[H^\š[Y[[ÛİY˜XÚİ\ÛXZ[”™XY[™\ÜÈÃBˆØ\ÙH™XYCBˆØ\ÙHØY[™ÃBˆØ\ÙH[˜]˜Z[X›CBŸCBƒB™[[HX[X[˜XÚİ\™\İÜ™TØÛÜNˆÙ[™X›HÃBˆØ\ÙH\Ñ]šXÙSÛ›CBˆØ\ÙH™\XÙQ]™\]Ú\™CBƒBˆ˜\ˆÙY\ĞÚ[™Ù\ÓÛ•\Ñ]šXÙNˆ›ÛÛÃBˆİÚ]ÚÙ[ˆÃBˆØ\ÙH\Ñ]šXÙSÛ›NƒBˆ™]\›ˆYCBˆØ\ÙHœ™\XÙQ]™\]Ú\™NƒBˆ™]\›ˆ˜[ÙCBˆCBˆCBŸCBƒB™[[H˜XÚİ\™XY\•\ØØ[S[Ù[™\İÜ™TÛXŞHÃBˆİ]XÈ[˜È[Ù[˜[YUĞ\JBˆ[˜ÛÛZ[™Îˆİš[™ËBˆ™\Ù\™\Ñ]šXÙSØØ[Ù[Xİ[Ûˆ›ÛÛBˆ
HOˆİš[™ÏÈÃBˆ™\Ù\™\Ñ]šXÙSØØ[Ù[Xİ[ÛˆÈš[ˆ[˜ÛÛZ[™ÃBˆCBŸCBƒB™[[H^\š[Y[[ÛİYÛ˜\Úİ™\\˜][Ûˆ[˜ÚXÚÙYÙ[™X›HÃBˆØ\ÙH™XYJ^\š[Y[[ÛİYÛ˜\Úİ
CBˆØ\ÙHY™\œ™YÚ[TÛİ\˜Ù\ÓØYBˆØ\ÙHÛİ\˜Ù\Õ[˜]˜Z[X›CBˆØ\ÙH˜Z[YBƒBˆ˜\ˆÛ˜\Úİˆ^\š[Y[[ÛİYÛ˜\ÚİÈÃBˆİX\™Ø\ÙH]œ™XYJÛ˜\Úİ
HHÙ[ˆ[ÙHÈ™]\›ˆš[CBˆ™]\›ˆÛ˜\ÚİBˆCBŸCBƒBœİXİ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^ˆÛÙX›K\]X]X›KÙ[™X›HÃBˆ]›İšY\”˜]Õ˜[YNˆİš[™ÃBˆ]Ù[™\˜][Ûˆ[Bˆ][™[™ÒY[]Nˆİš[™ÏÃBˆ]İ]ÛÚ[™Ô›Ùš[RQÎˆÕURQCBˆ]™\İÜ™Y˜XÚÙ\”›Ùš[RQÎˆÕURQCBƒBˆ[š]
Bˆ›İšY\”˜]Õ˜[YNˆİš[™ËBˆÙ[™\˜][Ûˆ[Bˆ[™[™ÒY[]Nˆİš[™ÏËBˆİ]ÛÚ[™Ô›Ùš[RQÎˆÕURQKBˆ™\İÜ™Y˜XÚÙ\”›Ùš[RQÎˆÕURQHH×CBˆ
HÃBˆÙ[‹œ›İšY\”˜]Õ˜[YHH›İšY\”˜]Õ˜[YCBˆÙ[‹™Ù[™\˜][ÛˆHÙ[™\˜][ÛƒBˆÙ[‹œ[™[™ÒY[]HH[™[™ÒY[]CBˆÙ[‹›İ]ÛÚ[™Ô›Ùš[RQÈHİ]ÛÚ[™Ô›Ùš[RQÃBˆÙ[‹œ™\İÜ™Y˜XÚÙ\”›Ùš[RQÈH™\İÜ™Y˜XÚÙ\”›Ùš[RQÃBˆCBƒBˆš]˜]H[[HÛÙ[™ÒÙ^\Îˆİš[™ËÛÙ[™ÒÙ^HÃBˆØ\ÙH›İšY\”˜]Õ˜[YCBˆØ\ÙHÙ[™\˜][ÛƒBˆØ\ÙH[™[™ÒY[]CBˆØ\ÙHİ]ÛÚ[™Ô›Ùš[RQÃBˆØ\ÙH™\İÜ™Y˜XÚÙ\”›Ùš[RQÃBˆCBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ]ÛÛZ[™\ˆHHXÛÙ\‹˜ÛÛZ[™\ŠÙ^YYNˆÛÙ[™ÒÙ^\ËœÙ[ŠCBˆ›İšY\”˜]Õ˜[YHHHÛÛZ[™\‹™XÛÙJİš[™ËœÙ[‹›Ü’Ù^Nˆœ›İšY\”˜]Õ˜[YJCBˆÙ[™\˜][ÛˆHHÛÛZ[™\‹™XÛÙJ[œÙ[‹›Ü’Ù^Nˆ™Ù[™\˜][ÛŠCBˆ[™[™ÒY[]HHHÛÛZ[™\‹™XÛÙRY”™\Ù[
İš[™ËœÙ[‹›Ü’Ù^Nˆœ[™[™ÒY[]JCBˆİ]ÛÚ[™Ô›Ùš[RQÈHHÛÛZ[™\‹™XÛÙJÕURQKœÙ[‹›Ü’Ù^Nˆ›İ]ÛÚ[™Ô›Ùš[RQÊCBˆ™\İÜ™Y˜XÚÙ\”›Ùš[RQÈHHÛÛZ[™\‹™XÛÙRY”™\Ù[
BˆÕURQKœÙ[‹Bˆ›Ü’Ù^Nˆœ™\İÜ™Y˜XÚÙ\”›Ùš[RQÃBˆ
HÏÈ×CBˆCBŸCBƒB™[[H^\š[Y[[ÛİY˜XÚÙ\XØÛİ[›İ[™\TÛXŞHÃBˆİ]XÈ[˜È›Ùš[RQÕĞÛX\ŠBˆİ]ÛÚ[™Ô›Ùš[RQÎˆÙ]URQ‹Bˆ™\İÜ™Y˜XÚÙ\”›Ùš[RQÎˆÙ]URQƒBˆ
HOˆÙ]URQˆÃBˆİ]ÛÚ[™Ô›Ùš[RQËœİX˜Xİ[™Ê™\İÜ™Y˜XÚÙ\”›Ùš[RQÊCBˆCBŸCBƒB™[[H^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™ˆİš[™ËÛÙX›KÙ[™X›HÃBˆØ\ÙHÜ™[˜\PÛİY™\İÜ™CBˆØ\ÙHXØÛİ[›İ[™\CBŸCBƒB™[[H^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û”İ]Nˆİš[™ËÛÙX›KÙ[™X›HÃBƒBˆØ\ÙH™\\š[™ÃBˆØ\ÙH™\\™YBƒBˆØ\ÙHÙY\ØØ[Üš]P]]Üš^™YBƒBˆØ\ÙHÛÛ[Z]]]Üš^™YBƒBˆØ\ÙHÛÛ\]YBŸCBƒBœİXİ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İˆÛÙX›KÙ[™X›HÃBˆ]ØÚ[XU™\œÚ[Ûˆ[Bˆ]˜[œØXİ[Û’QˆURQBˆ˜\ˆİ]Nˆ^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û”İ]CBˆ]™XÛİ™\RÚ[™ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™Bˆ˜\ˆXØÛİ[›İ[™\PÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^ÃBˆ]\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\Nˆ›ÛÛBˆ]\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Ûˆ›ÛÛBˆ]ÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[ˆ[ÃBˆ]ÙY\ØØ[˜[œÜÜ^[ØYÒLMˆİš[™ÏÃBƒBˆ[š]
Bˆ˜[œØXİ[Û’QˆURQBˆİ]Nˆ^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û”İ]KBˆXØÛİ[›İ[™\PÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^ËBˆ\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\Nˆ›ÛÛBˆ\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Ûˆ›ÛÛBˆÙY\ØØ[˜[œÜÜ^[ØYˆ]OÈHš[Bˆ
HÃBˆØÚ[XU™\œÚ[ÛˆHƒBˆÙ[‹˜[œØXİ[Û’QH˜[œØXİ[Û’QBˆÙ[‹œİ]HHİ]CBˆ™XÛİ™\RÚ[™HXØÛİ[›İ[™\PÛÛ^OHš[BˆÈ›Ü™[˜\PÛİY™\İÜ™CBˆˆ˜XØÛİ[›İ[™\CBˆÙ[‹˜XØÛİ[›İ[™\PÛÛ^HXØÛİ[›İ[™\PÛÛ^BˆÙ[‹š\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HH\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\CBˆÙ[‹š\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[ÛˆH\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[ÛƒBˆÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[HÙY\ØØ[˜[œÜÜ^[ØYË˜Ûİ[BˆÚYˆØ[’[\Ü
Ü\ÒÚ]
CBˆÙY\ØØ[˜[œÜÜ^[ØYÒLMˆHÙY\ØØ[˜[œÜÜ^[ØY›X\ÃBˆÒLM‹š\Ú
]Nˆ	
CBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆCBˆÙ[ÙCBˆÙY\ØØ[˜[œÜÜ^[ØYÒLMˆHÙY\ØØ[˜[œÜÜ^[ØYOHš[Èš[ˆˆƒBˆÙ[™YƒBˆCBƒBˆ˜\ˆ\ÒÙY\ØØ[˜[œÜÜ^[ØYˆ›ÛÛÃBˆÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[OHš[Bˆ	‰ˆÙY\ØØ[˜[œÜÜ^[ØYÒLMˆOHš[BˆCBƒBˆ[˜È˜[Y]\ÒÙY\ØØ[˜[œÜÜ^[ØY
È^[ØYˆ]JHOˆ›ÛÛÃBˆİX\™]^XİY]PÛİ[HÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[Bˆ]^XİYYÙ\İHÙY\ØØ[˜[œÜÜ^[ØYÒLM‹Bˆ^[ØY˜Ûİ[OH^XİY]PÛİ[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆÚYˆØ[’[\Ü
Ü\ÒÚ]
CBˆ]YÙ\İHÒLM‹š\Ú
]Nˆ^[ØY
CBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆ™]\›ˆYÙ\İOH^XİYYÙ\İBˆÙ[ÙCBˆ™]\›ˆ^XİYYÙ\İš\Ñ[\CBˆÙ[™YƒBˆCBŸCBƒBœİXİ^\š[Y[[ÛİYÙY\ØØ[™\^Nˆ[˜ÚXÚÙYÙ[™X›HÃBˆ]˜[œØXİ[Û’QˆURQBˆ]ÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ]Û˜\Úİˆ^\š[Y[[ÛİYÛ˜\ÚİBŸCBƒB™[[H^\š[Y[[ÛİY˜XÚÙ\ÛX[\]]Üš]NˆÙ[™X›HÃBˆØ\ÙH›Û™CBˆØ\ÙH]]Üš^™Y
^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
CBˆØ\ÙH›ØÚÙYBŸCBƒBœİXİ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SİÛ™\œÚ\ˆÛÙX›KÙ[™X›HÃBˆ]ØÚ[XU™\œÚ[Ûˆ[Bˆ]˜[œØXİ[Û’QˆURQBˆ]™XÛİ™\RÚ[™ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™Bˆ]^[ØY]PÛİ[ˆ[Bˆ]^[ØYÒLMˆİš[™ÃBƒBˆ[š]
Bˆ˜[œØXİ[Û’QˆURQBˆ™XÛİ™\RÚ[™ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™Bˆ^[ØYˆ]CBˆ
HÃBˆØÚ[XU™\œÚ[ÛˆHCBˆÙ[‹˜[œØXİ[Û’QH˜[œØXİ[Û’QBˆÙ[‹œ™XÛİ™\RÚ[™H™XÛİ™\RÚ[™Bˆ^[ØY]PÛİ[H^[ØY˜Ûİ[BˆÚYˆØ[’[\Ü
Ü\ÒÚ]
CBˆ^[ØYÒLMˆHÒLM‹š\Ú
]Nˆ^[ØY
CBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆÙ[ÙCBˆ^[ØYÒLMˆHˆƒBˆÙ[™YƒBˆCBƒBˆ[˜È˜[Y]\ÊBˆ˜[œØXİ[Û’Q^XİY˜[œØXİ[Û’QˆURQBˆ™XÛİ™\RÚ[™^XİY™XÛİ™\RÚ[™ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™Bˆ^[ØYˆ]CBˆ
HOˆ›ÛÛÃBˆİX\™ØÚ[XU™\œÚ[ÛˆOHKBˆ˜[œØXİ[Û’QOH^XİY˜[œØXİ[Û’QBˆ™XÛİ™\RÚ[™OH^XİY™XÛİ™\RÚ[™Bˆ^[ØY]PÛİ[OH^[ØY˜Ûİ[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆÚYˆØ[’[\Ü
Ü\ÒÚ]
CBˆ]YÙ\İHÒLM‹š\Ú
]Nˆ^[ØY
CBˆ›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HCBˆš›Ú[™Y

CBˆ™]\›ˆ^[ØYÒLMˆOHYÙ\İBˆÙ[ÙCBˆ™]\›ˆ^[ØYÒLM‹š\Ñ[\CBˆÙ[™YƒBˆCBŸCBƒB™^[œÚ[Ûˆ›İYšXØ][Û‹“˜[YHÃBˆİ]XÈ]^\š[Y[[ÛİY™\İÜ™T™XÛİ™\QYÛÛ\]HH›İYšXØ][Û‹“˜[YJBˆ™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\QYÛÛ\]HƒBˆ
CBŸCBƒBœİXİ˜XÚİ\ÛÛXİ[ÛˆÛÙX›HÃBˆš]˜]Hİ]XÈ]X^[][R][PÛİ[HLÌBƒBˆ]YˆURQBˆ]˜[YNˆİš[™ÃBˆ]][\ÎˆÓXœ˜\R][WCBˆ]\ØÜš\[Ûˆİš[™ÏÃBƒBˆš]˜]H[[HÛÙ[™ÒÙ^\Îˆİš[™ËÛÙ[™ÒÙ^HÃBˆØ\ÙHY˜[YK][\Ë\ØÜš\[ÛƒBˆCBƒBˆËËÈÛÛœİ[YHXXÚ\œ˜^H[[Y[›İYÚ]ÈİÛˆXÛÙ\ˆÛÈÛ™HÜİ[HYYXCBˆËËÈY[]HØ[››İXZÙHH™\Ù[ÛÛXİ[Ûˆ
Üˆ™ZYÚ›Üš[™È˜[Y][\ÊCBˆËËÈ\Ø\X\‹ˆHÛÛXİ[Û‰ÜÈ][\ØÙ^H™[XZ[œÈ™\]Z\™YˆZ\ÜÚ[™ËÛ[BˆËËÈİ[˜Z[ÈHÛÛXİ[ÛˆXÛÙH[™\™Y›Ü™HØ[››İXÜ]Z\™H[\CBˆËËÈ™\XÙ[Y[]]Üš]KƒBˆš]˜]HİXİÜÜŞSXœ˜\R][\ÎˆXÛÙX›HÃBˆ]˜[Y\ÎˆÓXœ˜\R][WCBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ˜\ˆÛÛZ[™\ˆHHXÛÙ\‹[šÙ^YYÛÛZ[™\Š
CBˆYˆ]Ûİ[HÛÛZ[™\‹˜Ûİ[BˆÛİ[ˆ˜XÚİ\ÛÛXİ[Û‹›X^[][R][PÛİ[ÃBˆ›İÈXÛÙ[™Ñ\œ›Ü‹™]PÛÜœ\Y\œ›ÜŠBˆ[ˆÛÛZ[™\‹BˆXYÑ\ØÜš\[Ûˆ˜XÚİ\ÛÛXİ[ÛˆÛÛZ[œÈÛÈX[H][\ËˆƒBˆ
CBˆCBˆ˜\ˆXÛÙYˆÓXœ˜\R][WHH×CBˆXÛÙYœ™\Ù\™PØ\XÚ]JBˆZ[ŠÛÛZ[™\‹˜Ûİ[ÏÈ˜XÚİ\ÛÛXİ[Û‹›X^[][R][PÛİ[
CBˆ
CBˆ˜\ˆÛÛœİ[YYÛİ[HBˆÚ[HXÛÛZ[™\‹š\Ğ][™ÃBˆİX\™ÛÛœİ[YYÛİ[˜XÚİ\ÛÛXİ[Û‹›X^[][R][PÛİ[[ÙHÃBˆ›İÈXÛÙ[™Ñ\œ›Ü‹™]PÛÜœ\Y\œ›ÜŠBˆ[ˆÛÛZ[™\‹BˆXYÑ\ØÜš\[Ûˆ˜XÚİ\ÛÛXİ[ÛˆÛÛZ[œÈÛÈX[H][\ËˆƒBˆ
CBˆCBˆ]Ø[™Y]HHHÛÛZ[™\‹™XÛÙJÜÜŞSXœ˜\R][KœÙ[ŠCBˆÛÛœİ[YYÛİ[
ÏHCBˆYˆ]˜[YHHØ[™Y]K˜[YHÃBˆXÛÙY˜\[™
˜[YJCBˆCBˆCBˆ˜[Y\ÈHXÛÙYBˆCBˆCBƒBˆš]˜]HİXİÜÜŞSXœ˜\R][NˆXÛÙX›HÃBˆ]˜[YNˆXœ˜\R][OÃBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ˜[YHHOÈXœ˜\R][Jœ›ÛNˆXÛÙ\ŠCBˆCBˆCBƒBˆ[š]
YˆURQ˜[YNˆİš[™Ë][\ÎˆÓXœ˜\R][WK\ØÜš\[Ûˆİš[™ÏÊHÃBˆÙ[‹šYHYBˆÙ[‹›˜[YHH˜[YCBˆÙ[‹š][\ÈHÙ[‹œØ[š]^™Y][\Ê][\ÊCBˆÙ[‹™\ØÜš\[ÛˆH\ØÜš\[ÛƒBˆCBƒBˆ[š]
œ›ÛHÛÛXİ[ÛˆXœ˜\PÛÛXİ[ÛŠHÃBˆÙ[‹š[š]
BˆYˆÛÛXİ[Û‹šYBˆ˜[YNˆÛÛXİ[Û‹›˜[YKBˆ][\ÎˆÛÛXİ[Û‹š][\ËBˆ\ØÜš\[ÛˆÛÛXİ[Û‹™\ØÜš\[ÛƒBˆ
CBˆCBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ]ÛÛZ[™\ˆHHXÛÙ\‹˜ÛÛZ[™\ŠÙ^YYNˆÛÙ[™ÒÙ^\ËœÙ[ŠCBˆÙ[‹š[š]
BˆYˆHÛÛZ[™\‹™XÛÙJURQœÙ[‹›Ü’Ù^NˆšY
KBˆ˜[YNˆHÛÛZ[™\‹™XÛÙJİš[™ËœÙ[‹›Ü’Ù^Nˆ›˜[YJKBˆ][\ÎˆHÛÛZ[™\‹™XÛÙJÜÜŞSXœ˜\R][\ËœÙ[‹›Ü’Ù^Nˆš][\ÊK˜[Y\ËBˆ\ØÜš\[ÛˆHÛÛZ[™\‹™XÛÙRY”™\Ù[
İš[™ËœÙ[‹›Ü’Ù^Nˆ™\ØÜš\[ÛŠCBˆ
CBˆCBƒBˆ[˜È[˜ÛÙJÈ[˜ÛÙ\ˆ[˜ÛÙ\ŠH›İÜÈÃBˆ˜\ˆÛÛZ[™\ˆH[˜ÛÙ\‹˜ÛÛZ[™\ŠÙ^YYNˆÛÙ[™ÒÙ^\ËœÙ[ŠCBˆHÛÛZ[™\‹™[˜ÛÙJY›Ü’Ù^NˆšY
CBˆHÛÛZ[™\‹™[˜ÛÙJ˜[YK›Ü’Ù^Nˆ›˜[YJCBˆHÛÛZ[™\‹™[˜ÛÙJÙ[‹œØ[š]^™Y][\Ê][\ÊK›Ü’Ù^Nˆš][\ÊCBˆHÛÛZ[™\‹™[˜ÛÙRY”™\Ù[
\ØÜš\[Û‹›Ü’Ù^Nˆ™\ØÜš\[ÛŠCBˆCBƒBˆ˜\ˆØ[š]^™Y›Ü”\œÚ\İ[˜ÙNˆ˜XÚİ\ÛÛXİ[ÛˆÃBˆ˜XÚİ\ÛÛXİ[ÛŠYˆY˜[YNˆ˜[YK][\Îˆ][\Ë\ØÜš\[Ûˆ\ØÜš\[ÛŠCBˆCBƒBˆ[˜ÈÓXœ˜\PÛÛXİ[ÛŠ
HOˆXœ˜\PÛÛXİ[ÛˆÃBˆXœ˜\PÛÛXİ[ÛŠBˆYˆYBˆ˜[YNˆ˜[YKBˆ][\ÎˆÙ[‹œØ[š]^™Y][\Ê][\ÊKBˆ\ØÜš\[Ûˆ\ØÜš\[ÛƒBˆ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ[š]^™Y][\ÊÈ][\ÎˆÓXœ˜\R][WJHOˆÓXœ˜\R][WHÃBˆ\œ˜^J][\Ë˜ÛÛ\XİX\È][HOˆXœ˜\R][OÈ[ƒBˆİX\™]™\İ[H][KœÙX\˜Ú™\İ[œØ[š]^™Y›Ü”\œÚ\İ[˜ÙH[ÙHÈ™]\›ˆš[CBˆ™]\›ˆXœ˜\R][JÙX\˜Ú™\İ[ˆ™\İ[]PYYˆ][K™]PYY
CBˆKœ™Yš^
X^[][R][PÛİ[
JCBˆCBŸCBƒB˜Û\ÜÈ˜XÚİ\X[˜YÙ\ˆÂˆİ]XÈ]Ú\™YH˜XÚİ\X[˜YÙ\Š
CBƒBˆİ]XÈ[˜ÈÜ]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ›ÛÛBˆ›Ùš[PØ\\™Q›YÎˆ›ÛÛÃBˆ
HOˆ›ÛÛÃBˆ^[ØYØ\ÑXÛÙY	‰ˆ
›Ùš[PØ\\™Q›YÈÏÈYJCBˆCBƒBˆš]˜]H]X[X[˜XÚİ\˜Z[\™SØÚÈH”ÓØÚÊ
Bˆš]˜]H˜\ˆX[X[˜XÚİ\˜Z[\™T™X\ÛÛˆİš[™ÏÂˆš]˜]H]X[X[™\İÜ™T™\İ[ØÚÈH”ÓØÚÊ
Bˆš]˜]H˜\ˆX[X[™\İÜ™Q˜Z[\™T™X\ÛÛˆİš[™ÏÂˆš]˜]H˜\ˆX[X[™\İÜ™R[\ÜY™XÛÜ™Ûİ[Hˆš]˜]H˜\ˆX[X[™\İÜ™T™\]Z\™\Ô™[][˜ÚH˜[ÙBƒBˆ˜\ˆ\İX[X[˜XÚİ\˜Z[\™T™X\ÛÛˆİš[™ÏÈÂˆX[X[˜XÚİ\˜Z[\™SØÚË›ØÚÊ
CBˆY™\ˆÈX[X[˜XÚİ\˜Z[\™SØÚË[›ØÚÊ
HCBˆ™]\›ˆX[X[˜XÚİ\˜Z[\™T™X\ÛÛƒBˆB‚ˆ˜\ˆ\İX[X[™\İÜ™Q˜Z[\™T™X\ÛÛˆİš[™ÏÈÂˆX[X[™\İÜ™T™\İ[ØÚË›ØÚÊ
BˆY™\ˆÈX[X[™\İÜ™T™\İ[ØÚË[›ØÚÊ
HBˆ™]\›ˆX[X[™\İÜ™Q˜Z[\™T™X\ÛÛ‚ˆB‚ˆ˜\ˆ\İX[X[™\İÜ™R[\ÜY™XÛÜ™Ûİ[ˆ[ÂˆX[X[™\İÜ™T™\İ[ØÚË›ØÚÊ
BˆY™\ˆÈX[X[™\İÜ™T™\İ[ØÚË[›ØÚÊ
HBˆ™]\›ˆX[X[™\İÜ™R[\ÜY™XÛÜ™Ûİ[ˆB‚ˆ˜\ˆ\İX[X[™\İÜ™T™\]Z\™\Ô™[][˜Úˆ›ÛÛÂˆX[X[™\İÜ™T™\İ[ØÚË›ØÚÊ
BˆY™\ˆÈX[X[™\İÜ™T™\İ[ØÚË[›ØÚÊ
HBˆ™]\›ˆX[X[™\İÜ™T™\]Z\™\Ô™[][˜ÚˆB‚ˆš]˜]H[˜È™XÛÜ™X[X[™\İÜ™T™\İ[
ˆ˜Z[\™T™X\ÛÛˆİš[™ÏËˆ[\ÜY™XÛÜ™Ûİ[ˆ[Hˆ™\]Z\™\Ô™[][˜Úˆ›ÛÛH˜[ÙBˆ
HÂˆX[X[™\İÜ™T™\İ[ØÚË›ØÚÊ
BˆY™\ˆÈX[X[™\İÜ™T™\İ[ØÚË[›ØÚÊ
HBˆX[X[™\İÜ™Q˜Z[\™T™X\ÛÛˆH˜Z[\™T™X\ÛÛ‚ˆX[X[™\İÜ™R[\ÜY™XÛÜ™Ûİ[H[\ÜY™XÛÜ™Ûİ[ˆX[X[™\İÜ™T™\]Z\™\Ô™[][˜ÚH™\]Z\™\Ô™[][˜ÚˆBƒBˆš]˜]H[˜È™XÛÜ™X[X[˜XÚİ\˜Z[\™T™X\ÛÛŠÈ™X\ÛÛˆİš[™ÏÊHÃBˆX[X[˜XÚİ\˜Z[\™SØÚË›ØÚÊ
CBˆY™\ˆÈX[X[˜XÚİ\˜Z[\™SØÚË[›ØÚÊ
HCBˆX[X[˜XÚİ\˜Z[\™T™X\ÛÛˆH™X\ÛÛƒBˆCBƒBˆš]˜]H[[H˜XÚİ\Ü™X][Û‘\œ›ÜˆØØ[^™Y\œ›ÜˆÃBˆØ\ÙHÚ\™YÛİ\˜ÙT^[ØYYÙ]^ÙYYY
[
CBˆØ\ÙHXİ]™T›Ùš[PÚ[™ÙYBˆØ\ÙH›Ùš[T›Üİ\•[œ™XYX›CBˆØ\ÙHXİ]™T›Ùš[PÛÛ\]Xš[]QÛXZ[œÕ[œ™XYX›JÔİš[™×JCBˆØ\ÙHš]˜]PÛİYÛÛ™šYİ\˜][Û’[˜ÛÛ\]CBƒBˆ˜\ˆ\œ›Ü‘\ØÜš\[Ûˆİš[™ÏÈÃBˆİÚ]ÚÙ[ˆÃBˆØ\ÙHœÚ\™YÛİ\˜ÙT^[ØYYÙ]^ÙYYY
]Ûİ[
NƒBˆ™]\›ˆ˜XÚİ\™YYÈ
Ûİ[
HY][Û˜[[˜Xİ]™K\›Ùš[HÛİ\˜ÙH^[ØY
ÊKˆ™[[İ™H[\ÙYXÚØYÙ\ÈÜˆ™YXÙHZ\ˆÚ^™H™Y›Ü™H^Ü[™ËˆƒBˆØ\ÙH˜Xİ]™T›Ùš[PÚ[™ÙYƒBˆ™]\›ˆ•HXİ]™H›Ùš[HÜˆ›Ùš[H›Üİ\ˆÚ[™ÙYÚ[HH˜XÚİ\Ø\È™Z[™ÈØ\\™YˆH^Ü[™ÈYØZ[‹ˆƒBˆØ\ÙHœ›Ùš[T›Üİ\•[œ™XYX›NƒBˆ™]\›ˆ•HØ]™Y›Ùš[H›Üİ\ˆÛİ[›İ™H™XYÛÈXÛ\ÙH™Y\ÙYÈ^Ü[ˆ]]Üš]]]™H˜[˜XÚÈ›Üİ\‹ˆ™\İÜ™HH˜[Y˜XÚİ\ÜˆY]H›Ùš[H›Üİ\‹[ˆHYØZ[‹ˆƒBˆØ\ÙH˜Xİ]™T›Ùš[PÛÛ\]Xš[]QÛXZ[œÕ[œ™XYX›J]ÛXZ[œÊNƒBˆ™]\›ˆ•HXİ]™H›Ùš[IÜÈ
ÛXZ[œËš›Ú[™Y
Ù\\˜]Üˆ‹ŠJH]HÛİ[›İ™H™XYˆXÛ\ÙH™Y\ÙYÈÜ™X]HH˜XÚİ\ÚÜÙHYØXŞHÛÛ\]Xš[]HÛÜHÛİ[\˜\ÙHX[H]HÚ[ˆ™\İÜ™YH[ˆÛ\ˆ™\œÚ[Û‹ˆƒBˆØ\ÙHœš]˜]PÛİYÛÛ™šYİ\˜][Û’[˜ÛÛ\]NƒBˆ™]\›ˆHš]˜]HÛİYÛÛ™šYİ\˜][ÛˆÛXZ[ˆÛİ[›İ™HØ\\™YÛÛ\][KÛÈXÛ\ÙHYH^\İ[™ÈÛİYÛ˜\Úİ[˜Ú[™ÙYˆƒBˆCBˆCBˆCBƒBˆš]˜]H[[H˜XÚİ\™\İÜ™Q\œ›ÜˆØØ[^™Y\œ›ÜˆÂˆØ\ÙHXİ]™T›Ùš[PÚ[™ÙYˆØ\ÙH[˜[YØİ[Y[ˆØ\ÙHZ\ÜÚ[™Ğ˜XÚİ\^[ØYˆØ\ÙH[œİ\ÜY™\œÚ[ÛŠİš[™ÊBƒBˆ˜\ˆ\œ›Ü‘\ØÜš\[Ûˆİš[™ÏÈÂˆİÚ]ÚÙ[ˆÂˆØ\ÙH˜Xİ]™T›Ùš[PÚ[™ÙY‚ˆ™]\›ˆ•HXİ]™H›Ùš[HÜˆ›Ùš[H›Üİ\ˆÚ[™ÙYÚ[HH™\İÜ™HØ\Èİ\[™ËˆH[\Ü[™ÈYØZ[‹ˆ‚ˆØ\ÙHš[˜[YØİ[Y[‚ˆ™]\›ˆ•\Èš[H\È›İH˜[YXÛ\ÙH˜XÚİ\”ÓÓˆØİ[Y[ˆ‚ˆØ\ÙH›Z\ÜÚ[™Ğ˜XÚİ\^[ØY‚ˆ™]\›ˆ•\È˜XÚİ\\È[˜ÛÛ\]Nˆ]Ù\È›İÛÛZ[ˆÙ][™ÜË›Ùš[\ËÛÛXİ[ÛœËÜˆØ]Ú\İÜKˆ‚ˆØ\ÙH[œİ\ÜY™\œÚ[ÛŠ]™\œÚ[ÛŠN‚ˆ™]\›ˆ•\È˜XÚİ\\Ù\È›Ü›X]™\œÚ[Ûˆ
™\œÚ[ÛŠKÚXÚ\ÈXÛ\ÙH™\œÚ[ÛˆØ[››İ™XYˆ\]HXÛ\ÙH[™HYØZ[‹ˆ‚ˆBˆBˆB‚ˆš]˜]HİXİX[X[™\İÜ™T™Y›YÚÂˆ]Ø]Ú™XÛÜ™Ûİ[ˆ[ˆ]™Y™\œ™YXİ]™T›Ùš[RQˆURQÂˆBƒBˆš]˜]HİXİXİ]™T›Ùš[TØÛÜUÚÙ[ˆ\]X]X›HÃBˆ]›Ùš[RQˆURQBˆ]Ù\šXÙ\ÑÙ[™\˜][Ûˆ[Bˆ]›Üİ\‘Ù[™\˜][ÛˆR[BˆCBƒBˆš]˜]HİXİ˜XÚİ\\XØ][Û”™\İ[ÃBˆ]]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆÙ]URQƒBˆCBƒBˆš]˜]HİXİØÛÜY˜XÚİ\\XØ][Û”™\İ[ÃBˆ]ØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ]]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆÙ]URQƒBˆCBƒBˆš]˜]HİXİš]˜]PÛÛ™šYİ\˜][Û”™\İÜ™T™\İ[ÃBˆ]Ø\Ô™\İÜ™Yˆ›ÛÛBˆ]]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆÙ]URQƒBˆCBƒBˆš]˜]HİXİÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛˆÃBˆ]™]š[İ\Õ˜[YNˆ›ÛÛBˆ]™\]Y\İY˜[YNˆ›ÛÛBˆ]Xİ]™T›Ùš[RQˆURQBˆ]\™Ù]\Ù\ÔÚ\™YY˜][Îˆ›ÛÛBˆ]\™Ù]İÜ™TÛ˜\ÚİˆÙ\šXÙTİÜ™TØÛÜK”İÜ™Qš[TÛ˜\ÚİÃBˆ]\™Ù]Ù][™ÜĞ™Y›Ü™U˜[œÚ][ÛˆÔİš[™Îˆ]WCBƒBˆ˜\ˆYİÚ]Úˆ›ÛÛÈ™]š[İ\Õ˜[YHOH™\]Y\İY˜[YHCBˆCBƒBˆš]˜]HİXİÚ\™TÙ\šXÙ\Ô™\İÜ™Tİ\ÃBˆ]˜[œØXİ[ÛˆÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛƒBˆ]ØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆCBƒBˆš]˜]HİXİ˜XÚİ\Ø\\™PÛÛ^ÃBˆ]ØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ]›Ùš[\ÎˆÔ›Ùš[WCBˆCBƒBˆİ]XÈ]X^[][SX[X[˜XÚİ\š[P]\ÈHL
ˆWÌ
ˆWÌBƒBˆš]˜]Hİ]XÈ]X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÈHLÌÌBƒBˆš]˜]Hİ]XÈ]X^[][TÚ\™YÛİ\˜ÙT^[ØY]\ÈHÌˆ
ˆWÌ
ˆWÌBƒBˆš]˜]Hİ]XÈ]X^[][TÚŞTİ™X[TØÜš\]\ÈHL
ˆWÌ
ˆWÌBˆš]˜]Hİ]XÈ]X^[][TÚŞTİ™X[P\˜Ú]™P]\ÈHŒ
ˆWÌ
ˆWÌBƒBƒBˆš]˜]H]š[SX[˜YÙ\ˆHš[SX[˜YÙ\‹™Y˜][Bˆš]˜]H]]Q›Ü›X]\ˆHTÓÎŒQ]Q›Ü›X]\Š
CBƒBˆš]˜]H˜\ˆÜ\]YTÚŞTİ™X[TİÜ˜YÙT›ÛİT“ˆT“ÈÃBˆİX\™]›ÛİHš[SX[˜YÙ\‹\›ÊBˆ›Üˆ˜\XØ][Û”İ\Ü\™XİÜKBˆ[ˆ\Ù\‘ÛXZ[“X\ÚÃBˆ
K™š\œİ[ÙHÈ™]\›ˆš[CBˆ™]\›ˆ›ÛİBˆ˜\[™[™Ô]ÛÛ\Û™[
‘XÛ\ÙH‹\Ñ\™XİÜNˆYJCBˆ˜\[™[™Ô]ÛÛ\Û™[
”ÚŞTİ™X[H‹\Ñ\™XİÜNˆYJCBˆCBƒBˆš]˜]H˜\ˆX[X[Ü\]YTÚŞTİ™X[TÛ˜\ÚİT“ˆT“ÈÃBˆÜ\]YTÚŞTİ™X[TİÜ˜YÙT›ÛİT“Ë˜\[™[™Ô]ÛÛ\Û™[
BˆÚŞTİ™X[SÜ\]YTİÜ˜YÙS^[İ]›X[X[˜XÚİ\š[[˜[YKBˆ\Ñ\™XİÜNˆ˜[ÙCBˆ
CBˆCBƒBˆš]˜]H˜\ˆÛİYÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“ˆT“ÈÃBˆÜ\]YTÚŞTİ™X[TİÜ˜YÙT›ÛİT“Ë˜\[™[™Ô]ÛÛ\Û™[
BˆÚŞTİ™X[SÜ\]YTİÜ˜YÙS^[İ]™^\š[Y[[ÛİY˜XÚİ\š[[˜[YKBˆ\Ñ\™XİÜNˆ˜[ÙCBˆ
CBˆCBƒBˆš]˜]H˜\ˆYØXŞSÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“ˆT“ÈÃBˆÜ\]YTÚŞTİ™X[TİÜ˜YÙT›ÛİT“Ë˜\[™[™Ô]ÛÛ\Û™[
BˆÚŞTİ™X[SÜ\]YTİÜ˜YÙS^[İ]›YØXŞTÚ\™Yš[[˜[YKBˆ\Ñ\™XİÜNˆ˜[ÙCBˆ
CBˆCBƒBˆš]˜]H[˜ÈØYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
™Y™\œš[™ÔØY™PÛİYˆ›ÛÛ
HOˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİÈÃBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ]X[X[Ø[™Y]\ÈHÛX[X[Ü\]YTÚŞTİ™X[TÛ˜\ÚİT“YØXŞSÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“CBˆ˜ÛÛ\XİX\È	CBˆ›X\È
	Ù[‹›X^[][SX[X[˜XÚİ\š[P]\Ë˜[ÙJHCBˆ]ÛİYØ[™Y]\ÈHØÛİYÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“CBˆ˜ÛÛ\XİX\È	CBˆ›X\È
	Ù[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ËYJHCBˆ]Ø[™Y]\ÈH™Y™\œš[™ÔØY™PÛİYBˆÈÛİYØ[™Y]\È
ÈX[X[Ø[™Y]\ÃBˆˆX[X[Ø[™Y]\È
ÈÛİYØ[™Y]\ÃBˆ›Üˆ
\›X^[][P]\Ë™\]Z\™\ÔØY™PÛİY›YÊH[ˆØ[™Y]\ÈÃBˆİX\™]˜[Y\ÈHOÈ\›œ™\Ûİ\˜ÙU˜[Y\Ê›Ü’Ù^\ÎˆËš\Ô™Yİ[\‘š[RÙ^K™š[TÚ^™RÙ^WJKBˆ˜[Y\Ëš\Ô™Yİ[\‘š[HOHYKBˆ
˜[Y\Ë™š[TÚ^™HÏÈ
HHX^[][P]\ËBˆ]]HHOÈ]JÛÛ[ÓÙˆ\›Ü[ÛœÎˆË›X\YY”ØY™WJKBˆ]K˜Ûİ[HX^[][P]\ËBˆ]Û˜\ÚİHOÈXÛÙ\‹™XÛÙJÚŞTİ™X[P˜XÚİ\Û˜\ÚİœÙ[‹œ›ÛNˆ]JKBˆ\™\]Z\™\ÔØY™PÛİY›YÈÛ˜\Úİš\ÔØY™PÛİYÛ˜\Úİ[ÙHÃBˆÛÛ[YCBˆCBˆ™]\›ˆÛ˜\ÚİBˆCBˆ™]\›ˆš[BˆCBƒBˆš]˜]H[˜È\œÚ\İÜ\]YTÚŞTİ™X[TÛ˜\Úİ
ÈÛ˜\ÚİˆÚŞTİ™X[P˜XÚİ\Û˜\Úİ
H›İÜÈÃBˆ]Ø[›ÛšXØ[Û˜\ÚİˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİBˆ]X^[][P]\Îˆ[Bˆ]\›ˆT“BˆYˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÃBˆİX\™]Ø[š]^™YH˜XÚİ\]KœÚŞTİ™X[TÛ˜\Úİ›Ü‘^\š[Y[[ÛİYŞ[˜ÊÛ˜\Úİ
KBˆ]ÛİYT“HÛİYÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[T™XYÛÜœ\š[JCBˆCBˆØ[›ÛšXØ[Û˜\ÚİHØ[š]^™YBˆX^[][P]\ÈHÙ[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÃBˆ\›HÛİYT“BˆH[ÙHÃBˆİX\™]X[X[T“HX[X[Ü\]YTÚŞTİ™X[TÛ˜\ÚİT“[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[S›ÔİXÚš[JCBˆCBˆØ[›ÛšXØ[Û˜\ÚİHÛ˜\ÚİBˆX^[][P]\ÈHÙ[‹›X^[][SX[X[˜XÚİ\š[P]\ÃBˆ\›HX[X[T“BˆCBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœÛÜYÙ^\×CBˆ]]HHH[˜ÛÙ\‹™[˜ÛÙJØ[›ÛšXØ[Û˜\Úİ
CBˆİX\™]K˜Ûİ[HX^[][P]\È[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[UÜš]Sİ]Ù”ÜXÙJCBˆCBˆHš[SX[˜YÙ\‹˜Ü™X]Q\™XİÜJBˆ]ˆ\›™[][™Ó\İ]ÛÛ\Û™[

KBˆÚ][\›YYX]Q\™XİÜšY\ÎˆYKBˆ]šX]\ÎˆËœÜÚ^\›Z\ÜÚ[ÛœÎˆ”Ó[X™\Š˜[YNˆ[MŠÍÌ
JWCBˆ
CBˆH]KÜš]JÎˆ\›Ü[ÛœÎˆ˜]ÛZXÊCBˆ›Üˆš[[˜[YH[ˆÚŞTİ™X[SÜ\]YTİÜ˜YÙS^[İ]™š[[˜[Y\Ò[˜[Y]YY\•Üš]JBˆ\ÔØY™PÛİYÛ˜\ÚİˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİBˆ
HÃBˆ]İ[UT“H\›™[][™Ó\İ]ÛÛ\Û™[

K˜\[™[™Ô]ÛÛ\Û™[
š[[˜[YJCBˆYˆš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆİ[UT“œ]
HÃBˆHš[SX[˜YÙ\‹œ™[[İ™R][J]ˆİ[UT“
CBˆCBˆCBˆCBƒBˆš]˜]H[˜ÈÛX\YÜYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
\ÔØY™PÛİYÛ˜\Úİˆ›ÛÛ
HÃBˆ]Ø[™Y]\ÎˆÕT“×CBˆYˆ\ÔØY™PÛİYÛ˜\ÚİÃBˆØ[™Y]\ÈHØÛİYÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“CBˆH[ÙHÃBˆØ[™Y]\ÈHÃBˆX[X[Ü\]YTÚŞTİ™X[TÛ˜\ÚİT“BˆYØXŞSÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“BˆÛİYÜ\]YTÚŞTİ™X[TÛ˜\ÚİT“BˆCBˆCBˆ›Üˆ\›[ˆØ[™Y]\Ë˜ÛÛ\XİX\
È	JHÚ\™Hš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆ\›œ]
HÃBˆÈÃBˆHš[SX[˜YÙ\‹œ™[[İ™R][J]ˆ\›
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘˜Z[YÈÛX\ˆYÜYÜ\]YHÚŞTİ™X[HÛ˜\Úİ\œ›Ü•\OW
İš[™Ê™Y›Xİ[™Îˆ\JÙˆ\œ›ÜŠJJH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆCBˆCBƒBˆš]˜]H[˜È\™›Ü›SÛ“XZ[•™XY
ÈÛÜšÎˆ

HOˆ›ÚY
HÃBˆYˆ™XYš\ÓXZ[•™XYÃBˆÛÜšÊ
CBˆH[ÙHÃBˆ\Ü]Ú]Y]YK›XZ[‹œŞ[˜Ê^Xİ]NˆÛÜšÊCBˆCBˆCBƒBˆš]˜]H[˜ÈXİ]™T›Ùš[TØÛÜUÚÙ[Š
HOˆXİ]™T›Ùš[TØÛÜUÚÙ[ˆÃBˆ˜\ˆÚÙ[ˆHXİ]™T›Ùš[TØÛÜUÚÙ[ŠBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQBˆÙ\šXÙ\ÑÙ[™\˜][ÛˆLKBˆ›Üİ\‘Ù[™\˜][ÛˆBˆ
CBˆ\™›Ü›SÛ“XZ[•™XYÃBˆÚÙ[ˆHXİ]™T›Ùš[TØÛÜUÚÙ[ŠBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆÙ\šXÙ\ÑÙ[™\˜][ÛˆÙ\šXÙTİÜ™TØÛÜK™Ù[™\˜][Û‹Bˆ›Üİ\‘Ù[™\˜][Ûˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛƒBˆ
CBˆCBˆ™]\›ˆÚÙ[ƒBˆCBƒBˆš]˜]H[˜È˜XÚİ\Ø\\™PÛÛ^

HOˆ˜XÚİ\Ø\\™PÛÛ^ÈÃBˆ˜\ˆÛÛ^ˆ˜XÚİ\Ø\\™PÛÛ^ÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]X[˜YÙ\ˆH›Ùš[SX[˜YÙ\‹œÚ\™YBˆİX\™]›Ùš[\ÈHX[˜YÙ\‹œ›Ùš[\Ñ›Ü“YYXTİ]TŞ[˜È[ÙHÈ™]\›ˆCBˆÛÛ^H˜XÚİ\Ø\\™PÛÛ^
BˆØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ŠBˆ›Ùš[RQˆX[˜YÙ\‹˜Xİ]™T›Ùš[RQBˆÙ\šXÙ\ÑÙ[™\˜][ÛˆÙ\šXÙTİÜ™TØÛÜK™Ù[™\˜][Û‹Bˆ›Üİ\‘Ù[™\˜][ÛˆX[˜YÙ\‹œ›Üİ\‘Ù[™\˜][ÛƒBˆ
KBˆ›Ùš[\Îˆ›Ùš[\ÃBˆ
CBˆCBˆ™]\›ˆÛÛ^BˆCBƒBˆš]˜]H[˜ÈXİ]™T›Ùš[TØÛÜR\Ğİ\œ™[
BˆÈÚÙ[ˆXİ]™T›Ùš[TØÛÜUÚÙ[‹Bˆ[˜ÛY[™Ô›Üİ\ˆ›ÛÛHYCBˆ
HOˆ›ÛÛÃBˆ˜\ˆ\Ğİ\œ™[H˜[ÙCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ\Ğİ\œ™[H›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOHÚÙ[‹œ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
ÚÙ[‹œÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ
Z[˜ÛY[™Ô›Üİ\ƒBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOHÚÙ[‹œ›Üİ\‘Ù[™\˜][ÛŠCBˆCBˆ™]\›ˆ\Ğİ\œ™[BˆCBƒBˆš]˜]Hİ]XÈ[˜È\œÙU\Ù\”˜][™ÜÊÈ˜][™ÜÎˆÔİš[™Îˆ[WJHOˆÔİš[™ÎˆİX›WHÃBˆXİ[Û˜\J[š\]YRÙ^\ÕÚ]˜[Y\Îˆ˜][™ÜË˜ÛÛ\XİX\ÈÙ^K˜[YHOˆ
İš[™ËİX›JOÈ[ƒBˆ][Y\šXÕ˜[YNˆİX›OÃBˆYˆ][X™\ˆH˜[YH\ÏÈ”Ó[X™\ˆÃBˆ[Y\šXÕ˜[YHH[X™\‹™İX›U˜[YCBˆH[ÙHYˆ]˜[YHH˜[YH\ÏÈİX›HÃBˆ[Y\šXÕ˜[YHH˜[YCBˆH[ÙHYˆ]˜[YHH˜[YH\ÏÈ[ÃBˆ[Y\šXÕ˜[YHHİX›J˜[YJCBˆH[ÙHÃBˆ[Y\šXÕ˜[YHHš[BˆCBƒBˆİX\™][Y\šXÕ˜[YH[ÙHÈ™]\›ˆš[CBˆ]š[š]U˜[YHH[Y\šXÕ˜[YKš\Ñš[š]HÈ[Y\šXÕ˜[YHˆCBˆ][”İ\˜[YHH
š[š]U˜[YH
ˆŠKœ›İ[™Y

HÈƒBˆ™]\›ˆ
Ù^KX^
KZ[ŠL[”İ\˜[YJJJCBˆJCBˆCBƒBˆİ]XÈ[˜È˜XÚÙ\”İ]UÚ]İ]Ü™Y[X[ÊÈİ]Nˆ˜XÚÙ\”İ]JHOˆ˜XÚÙ\”İ]HÃBˆ˜\ˆØ[š]^™YHİ]CBˆØ[š]^™Y˜XØÛİ[ÈHİ]K˜XØÛİ[Ë›X\ÈXØÛİ[[ƒBˆ˜\ˆY]Y]SÛ›HHXØÛİ[BˆY]Y]SÛ›K˜XØÙ\ÜÕÚÙ[ˆHˆƒBˆY]Y]SÛ›Kœ™Yœ™\ÚÚÙ[ˆHš[BˆY]Y]SÛ›K™^\™\Ğ]Hš[Bˆ™]\›ˆY]Y]SÛ›CBˆCBˆ™]\›ˆØ[š]^™YBˆCBƒBˆš]˜]HİXİYØXŞPÛİYYYXTİ]P]]Üš]HÃBˆ]›Ùš[RQˆURQBˆ]Ù][™ÜÎˆYYXTİ]SYØXŞT™\İÜ™TÙ][™ÔÛ˜\ÚİBƒBˆ]ÛÛXİ[ÛœÎˆÓXœ˜\PÛÛXİ[Û—OÃBˆ]›ÙÜ™\ÜÎˆ›ÙÜ™\ÜÑ]OÃBˆ]˜][™ÜÎˆ
˜[Y\ÎˆÔİš[™ÎˆİX›WK›İ\ÎˆÔİš[™Îˆİš[™×JOÃBˆ]Ø][ÙÜÎˆĞØ][Ù×OÃBˆCBƒBˆš]˜]H[˜ÈØ\\™SYØXŞPÛİYYYXTİ]P]]Üš]J
HOˆYØXŞPÛİYYYXTİ]P]]Üš]HÃBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™Bˆ]\œÚ\İ[ÛXZ[ˆÔİš[™Îˆ[WCBˆYˆ][™RY[YšY\ˆH[™K›XZ[‹˜[™RY[YšY\ˆÃBˆ\œÚ\İ[ÛXZ[ˆHY˜][Ëœ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆ[™RY[YšY\ŠHÏÈÎ—CBˆH[ÙHÃBƒBˆ\œÚ\İ[ÛXZ[ˆHY˜][Ë™Xİ[Û˜\T™\™\Ù[][ÛŠ
CBˆCBƒBˆ˜\ˆÛÛXİ[ÛœÎˆÓXœ˜\PÛÛXİ[Û—OÃBˆ˜\ˆ›ÙÜ™\ÜÎˆ›ÙÜ™\ÜÑ]OÃBˆ˜\ˆ˜][™ÜÎˆ
˜[Y\ÎˆÔİš[™ÎˆİX›WK›İ\ÎˆÔİš[™Îˆİš[™×JOÃBˆ˜\ˆØ][ÙÜÎˆĞØ][Ù×OÃBˆ\™›Ü›SÛ“XZ[•™XYÃBƒBˆ]›Ùš[SX[˜YÙ\ˆH›Ùš[SX[˜YÙ\‹œÚ\™YBˆİX\™›Ùš[SX[˜YÙ\‹œ›Üİ\”İÜ™R\Ô™XYX›H[ÙHÈ™]\›ˆCBˆ]İÛ™\ˆH›Ùš[SX[˜YÙ\‹˜Xİ]™T›Ùš[RQBˆÛÛXİ[ÛœÈHXœ˜\SX[˜YÙ\‹œÚ\™Y˜ÛÛXİ[ÛœÊ›Ü”›Ùš[NˆİÛ™\ŠCBˆ›ÙÜ™\ÜÈH›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Yœ›ÙÜ™\ÜÑ]J›Ü”›Ùš[NˆİÛ™\ŠCBˆYˆ]Z\ˆH\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ˜][™ÜĞ[™›İ\Ê›Ü”›Ùš[NˆİÛ™\ŠHÃBˆ˜][™ÜÈH
˜[Y\ÎˆZ\‹œ˜][™ÜË›İ\ÎˆZ\‹››İ\ÊCBˆCBˆØ][ÙÜÈHØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜÑ›Ü˜XÚİ\
›Ü”›Ùš[NˆİÛ™\ŠCBˆCBƒBˆ™]\›ˆYØXŞPÛİYYYXTİ]P]]Üš]JBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆÙ][™ÜÎˆYYXTİ]SYØXŞT™\İÜ™TÙ][™ÔÛ˜\Úİ
\œÚ\İ[ÛXZ[ˆ\œÚ\İ[ÛXZ[ŠKBˆÛÛXİ[ÛœÎˆÛÛXİ[ÛœËBˆ›ÙÜ™\ÜÎˆ›ÙÜ™\ÜËBˆ˜][™ÜÎˆ˜][™ÜËBˆØ][ÙÜÎˆØ][ÙÜÃBˆ
CBˆCBƒBˆš]˜]H[˜È™\İÜ™SYØXŞPÛİYYYXTİ]P]]Üš]JÈ]]Üš]NˆYØXŞPÛİYYYXTİ]P]]Üš]JHÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™Bˆ]]Üš]KœÙ][™ÜËœ™\İÜ™JÎˆY˜][ÊCBƒBˆYˆ]ÛÛXİ[ÛœÈH]]Üš]K˜ÛÛXİ[ÛœÈÃBˆXœ˜\SX[˜YÙ\‹œÚ\™Yœ™\XÙPÛÛXİ[ÛœÑ›Ü“YYXTİ]JÛÛXİ[ÛœÊCBˆCBˆYˆ]›ÙÜ™\ÜÈH]]Üš]Kœ›ÙÜ™\ÜÈÃBˆ›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Yœ™\XÙT›ÙÜ™\ÜÑ]Q›Ü”™\İÜ™JBˆ›ÙÜ™\ÜËBˆ^XİY›Ùš[RQˆ]]Üš]Kœ›Ùš[RQBˆ
CBˆCBˆYˆ]˜][™ÜÈH]]Üš]Kœ˜][™ÜÈÃBˆ\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ™\İÜ™T˜][™ÜĞ[™›İ\ÊBˆ˜][™ÜÎˆ˜][™ÜË˜[Y\ËBˆ›İ\Îˆ˜][™ÜË››İ\ÃBˆ
CBˆCBƒBˆYˆ]Ø][ÙÜÈH]]Üš]K˜Ø][ÙÜÈÃBˆ]Ø][ÙÓX[˜YÙ\ˆHØ][ÙÓX[˜YÙ\‹œÚ\™YBˆØ][ÙÓX[˜YÙ\‹œÙ]\™›Ü›X[˜ÙS[ÙQ[˜X›Y
BˆY˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™[˜X›YÙ^JCBˆ
CBˆØ][ÙÓX[˜YÙ\‹˜Ø][ÙÜÈHØ][ÙÜÃBˆØ][ÙÓX[˜YÙ\‹œØ]™PØ][ÙÜÊ
CBˆCBƒBˆÛYPØ][ÙÓ^[İ]İÜ™KœÚ\™Yœ™[ØYœ›ÛTİÜ˜YÙJ
CBˆ\ÚÈÈXZ[XİÜˆ[ƒBˆXÛ\ÙU[YKœÚ\™Yœ™[ØYYYXP\X\˜[˜ÙQœ›ÛQY˜][Ê
CBˆCBˆCBˆCBƒBˆ[˜ÈÜ™X]P˜XÚİ\

HOˆT“ÈÃBˆ™XÛÜ™X[X[˜XÚİ\˜Z[\™T™X\ÛÛŠš[
CBˆİX\™\ÔÚŞTİ™X[P˜XÚİ\ÛXZ[”™XYJ
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\Y™\œ™Y™XØ]\ÙHHÚŞTİ™X[HYÚ[ˆX[˜YÙ\ˆ\Èİ[ØY[™ÎÈ›È\X[˜XÚİ\Ø\ÈÜš][ˆ‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆ™XÛÜ™X[X[˜XÚİ\˜Z[\™T™X\ÛÛŠBˆ”Ûİ\˜Ù\È\™Hİ[ØY[™ËˆØZ]H[ÛY[[™HYØZ[‹ˆƒBˆ
CBˆ™]\›ˆš[BˆCBˆÈÃBˆ]˜XÚİ\]HHHØ]\˜XÚİ\]J
CBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœ™]Tš[YœÛÜYÙ^\×CBƒBˆ]œÛÛ‘]HHH[˜ÛÙ\‹™[˜ÛÙJ˜XÚİ\]JCBˆİX\™œÛÛ‘]K˜Ûİ[HÙ[‹›X^[][SX[X[˜XÚİ\š[P]\È[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\Ø\È›İÜš][ˆ™XØ]\ÙHH[˜ÛÙYØİ[Y[^ÙYYYHLPˆØY™]H[Z]‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™XÛÜ™X[X[˜XÚİ\˜Z[\™T™X\ÛÛŠBˆ•H˜XÚİ\^ÙYYYHLPˆØY™]H[Z]ˆ™[[İ™H\™ÙHÛİ\˜ÙHXÚØYÙ\È[™HYØZ[‹ˆƒBˆ
CBˆ™]\›ˆš[BˆCBƒBˆ][Y\İ[\H]J
CBˆ]›Ü›X]\ˆH]Q›Ü›X]\Š
CBˆ›Ü›X]\‹™]Q›Ü›X]H^^^KSSKYÒ[[K\ÜÈƒBˆ]š[[˜[YHH‘XÛ\ÙWĞ˜XÚİ\×
›Ü›X]\‹œİš[™Êœ›ÛNˆ[Y\İ[\
JKšœÛÛˆƒBƒBˆ]Øİ[Y[Ñ\ˆHš[SX[˜YÙ\‹\›Ê›Üˆ™Øİ[Y[\™XİÜK[ˆ\Ù\‘ÛXZ[“X\ÚÊVÌCBˆ]˜XÚİ\T“HØİ[Y[Ñ\‹˜\[™[™Ô]ÛÛ\Û™[
š[[˜[YJCBƒBˆHœÛÛ‘]KÜš]JÎˆ˜XÚİ\T“Ü[ÛœÎˆ˜]ÛZXÊCBˆÙÙÙ\‹œÚ\™Y›ÙÊ˜XÚİ\Ü™X]Y]ˆ
˜XÚİ\T“œ]
H‹\Nˆ’[™›ÈŠCBƒBˆ™]\›ˆ˜XÚİ\T“BˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ‘˜Z[YÈÜ™X]H˜XÚİ\ˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\Nˆ‘\œ›ÜˆŠCBˆ™XÛÜ™X[X[˜XÚİ\˜Z[\™T™X\ÛÛŠ\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠCBˆ™]\›ˆš[BˆCBˆCBƒBˆ[˜ÈÜ™X]Q^\š[Y[[ÛİYÛ˜\Úİ]J
H\Ş[˜ÈOˆ]OÈÃBˆ]ØZ]Ü™X]Q^\š[Y[[ÛİYÛ˜\Úİ

OË™]CBˆCBƒBˆXZ[XİÜƒBˆ[˜ÈÜ™X]PXØÛİ[›İ[™\T™XÛİ™\TÛ˜\Úİ

HOˆ^\š[Y[[ÛİYÛ˜\ÚİÈÃBˆ™\\™PXØÛİ[›İ[™\T™XÛİ™\TÛ˜\Úİ

KœÛ˜\ÚİBˆCBƒBˆXZ[XİÜƒBˆ[˜È™\\™PXØÛİ[›İ[™\T™XÛİ™\TÛ˜\Úİ

HOˆ^\š[Y[[ÛİYÛ˜\Úİ™\\˜][ÛˆÃBˆİÚ]ÚÚŞTİ™X[P˜XÚİ\ÛXZ[”™XY[™\ÜÊ
HÃBˆØ\ÙHœ™XYNƒBˆœ™XZÃBˆØ\ÙH›ØY[™ÎƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆXØÛİ[X›İ[™\H™XÛİ™\HÛ˜\ÚİY™\œ™YÚ[HÚŞTİ™X[Hİ]H\ÈØY[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ™Y™\œ™YÚ[TÛİ\˜Ù\ÓØYBˆØ\ÙH[˜]˜Z[X›NƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆXØÛİ[X›İ[™\H™XÛİ™\HÛ˜\Úİ™Y\ÙY™XØ]\ÙHÚŞTİ™X[Hİ]H˜Z[YÈØY‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆœÛİ\˜Ù\Õ[˜]˜Z[X›CBˆCBˆÈÃBˆ]Û˜\ÚİHHØ]\˜XÚİ\]JBˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİˆYKBˆ[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÎˆYCBˆ
CBˆİX\™Û˜\Úİœš]˜]PÛİYÛÛ™šYİ\˜][Û•Ø\ĞØ\\™YÛÛ\][H[ÙHÃBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹œš]˜]PÛİYÛÛ™šYİ\˜][Û’[˜ÛÛ\]CBˆCBƒBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœ™]Tš[YœÛÜYÙ^\×CBˆ]]HHH[˜ÛÙ\‹™[˜ÛÙJÛ˜\Úİ
CBˆİX\™]K˜Ûİ[HÙ[‹›X^[][SX[X[˜XÚİ\š[P]\È[ÙHÃBˆ›İÈ›İ[™YT“Ù\ÜÚ[Û‘\œ›Ü‹œ™\ÜÛœÙUÛÓ\™ÙJBˆX^[][P]\ÎˆÙ[‹›X^[][SX[X[˜XÚİ\š[P]\ÃBˆ
CBˆCBˆ™]\›ˆœ™XYJBˆ^\š[Y[[ÛİYÛ˜\Úİ
Bˆ]Nˆ]KBˆ›Ûİš[ˆ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[
BˆÛ˜\ÚİˆÛ˜\ÚİBˆ[˜ÛÙY]Nˆ]CBˆ
CBˆ
CBˆ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘˜Z[YÈÜ™X]H›İXİYXØÛİ[X›İ[™\H™XÛİ™\HÛ˜\Úİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ™˜Z[YBˆCBˆCBƒBˆ˜\ˆ˜XÚİ\ÛXZ[”™XY[™\ÜÎˆ^\š[Y[[ÛİY˜XÚİ\ÛXZ[”™XY[™\ÜÈÃBˆÚŞTİ™X[P˜XÚİ\ÛXZ[”™XY[™\ÜÊ
CBˆCBƒBˆ˜\ˆ\Ğ˜XÚİ\ÛXZ[”™XYQ›Ü”Û˜\ÚİÎˆ›ÛÛÃBˆ\ÔÚŞTİ™X[P˜XÚİ\ÛXZ[”™XYJ
CBˆCBƒBˆ[˜ÈÜ™X]Q^\š[Y[[ÛİYÛ˜\Úİ

H\Ş[˜ÈOˆ^\š[Y[[ÛİYÛ˜\ÚİÈÃBˆ]ØZ]™\\™Q^\š[Y[[ÛİYÛ˜\Úİ

KœÛ˜\ÚİBˆCBƒBˆ[˜È™\\™Q^\š[Y[[ÛİYÛ˜\Úİ

H\Ş[˜ÈOˆ^\š[Y[[ÛİYÛ˜\Úİ™\\˜][ÛˆÃBˆİÚ]ÚÚŞTİ™X[P˜XÚİ\ÛXZ[”™XY[™\ÜÊ
HÃBˆØ\ÙHœ™XYNƒBˆœ™XZÃBˆØ\ÙH›ØY[™ÎƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘^\š[Y[[ÛİYÛ˜\ÚİY™\œ™YÚ[HÚŞTİ™X[Hİ]H\ÈØY[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ™Y™\œ™YÚ[TÛİ\˜Ù\ÓØYBˆØ\ÙH[˜]˜Z[X›NƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘^\š[Y[[ÛİYÛ˜\Úİ™Y\ÙY™XØ]\ÙHÚŞTİ™X[Hİ]H˜Z[YÈØY‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆœÛİ\˜Ù\Õ[˜]˜Z[X›CBˆCBˆÈÃBˆ]Û˜\ÚİHHØ]\˜XÚİ\]J\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİˆYJCBˆœ™YXİY›Ü‘^\š[Y[[ÛİYŞ[˜Êİš\ÚŞTİ™X[P\˜Ú]™\ÎˆYJCBˆİX\™Û˜\Úİœš]˜]PÛİYÛÛ™šYİ\˜][Û•Ø\ĞØ\\™YÛÛ\][H[ÙHÃBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹œš]˜]PÛİYÛÛ™šYİ\˜][Û’[˜ÛÛ\]CBˆCBˆ™]\›ˆœ™XYJH]ØZ]\ÚË™]XÚY
š[Üš]Nˆ][]JHÃBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœÛÜYÙ^\×CBˆ˜\ˆ›İ[™YÛ˜\ÚİHÛ˜\ÚİBˆ˜\ˆ]HHH[˜ÛÙ\‹™[˜ÛÙJ›İ[™YÛ˜\Úİ
CBƒBˆYˆ]K˜Ûİ[ˆÙ[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ËBˆ˜\ˆÚŞTİ™X[HH›İ[™YÛ˜\ÚİœÚŞTİ™X[HÃBˆ]\˜Ú]™R[™^\ÈHÚŞTİ™X[KœYÚ[œËš[™XÙ\ÃBˆ™š[\ˆÈÚŞTİ™X[KœYÚ[œÖÉK˜\˜Ú]™T^[ØYOHš[CBˆœÛÜYÃBˆ
ÚŞTİ™X[KœYÚ[œÖÉK˜\˜Ú]™T^[ØYË˜Ûİ[ÏÈ
CBˆˆ
ÚŞTİ™X[KœYÚ[œÖÉWK˜\˜Ú]™T^[ØYË˜Ûİ[ÏÈ
CBˆCBˆ›Üˆ[™^[ˆ\˜Ú]™R[™^\ÈÃBˆÚŞTİ™X[KœYÚ[œÖÚ[™^K˜\˜Ú]™T^[ØYHš[BˆÚŞTİ™X[KœYÚ[œÖÚ[™^Kœ^[ØYØ\Ô™YXİYHYCBˆ›İ[™YÛ˜\ÚİœÚŞTİ™X[HHÚŞTİ™X[CBˆ]HHH[˜ÛÙ\‹™[˜ÛÙJ›İ[™YÛ˜\Úİ
CBˆYˆ]K˜Ûİ[HÙ[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÈÈœ™XZÈCBˆCBˆCBƒBˆİX\™]K˜Ûİ[HÙ[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\È[ÙHÃBˆ›İÈ›İ[™YT“Ù\ÜÚ[Û‘\œ›Ü‹œ™\ÜÛœÙUÛÓ\™ÙJBˆX^[][P]\ÎˆÙ[‹›X^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÃBˆ
CBˆCBˆ™]\›ˆ^\š[Y[[ÛİYÛ˜\Úİ
Bˆ]Nˆ]KBˆ›Ûİš[ˆ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[
BˆÛ˜\Úİˆ›İ[™YÛ˜\ÚİBˆ[˜ÛÙY]Nˆ]CBˆ
CBˆ
CBˆK˜[YJCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ‘˜Z[YÈÜ™X]H^\š[Y[[PÛİYÛ˜\Úİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\NˆšPÛİYŠCBˆ™]\›ˆ™˜Z[YBˆCBˆCBƒBˆ[˜È^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[
œ›ÛH]Nˆ]JHOˆ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[ÈÃBˆÈÃBˆİX\™Ù[‹™^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
]JH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊÛİYÛ˜\Úİ\Ù\ÈH™]Ù\ˆ[œİ\ÜYØÚ[XH‹\NˆÛİYŞ[˜ÈŠCBˆ™]\›ˆš[BˆCBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ]Û˜\ÚİHHXÛÙ\‹™XÛÙJ˜XÚİ\]KœÙ[‹œ›ÛNˆ]JKœ™YXİY›Ü‘^\š[Y[[ÛİYŞ[˜Ê
CBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœÛÜYÙ^\×CBˆ]Ø[›ÛšXØ[]HHH[˜ÛÙ\‹™[˜ÛÙJÛ˜\Úİ
CBˆ™]\›ˆ^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[
Û˜\ÚİˆÛ˜\Úİ[˜ÛÙY]NˆØ[›ÛšXØ[]JCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ‘˜Z[YÈ[œÜXİ^\š[Y[[ÛİYÛ˜\Úİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\NˆÛİYŞ[˜ÈŠCBˆ™]\›ˆš[BˆCBˆCBƒBˆ[˜È™\İÜ™Q^\š[Y[[ÛİYÛ˜\Úİ
Bˆœ›ÛH]Nˆ]KBˆ™\Ù\™SYYXTİ]Q›ÜÛİYÚ]ˆ›ÛÛHYCBˆ
H\Ş[˜ÈOˆ^\š[Y[[ÛİY™\İÜ™T™\İ[ÈÃBˆ˜\ˆÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛˆÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛÃBˆÈÃBˆİX\™Ù[‹™^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
]JH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ”™Y\ÙYÈ™\İÜ™HH™]Ù\ˆ[œİ\ÜYÛİYØÚ[XH‹\NˆÛİYŞ[˜ÈŠCBˆ™]\›ˆš[BˆCBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ˜\ˆÛ˜\ÚİHHXÛÙ\‹™XÛÙJ˜XÚİ\]KœÙ[‹œ›ÛNˆ]JKœ™YXİY›Ü‘^\š[Y[[ÛİYŞ[˜Ê
CBˆÛ˜\Úİœ™[[İ™T™XY\‘ÛXZ[œÕÚ]İ]ÛÛ\]Tš]˜]PÛİY]]Üš]J
CBˆ][[™YØÛÜHHXİ]™T›Ùš[TØÛÜUÚÙ[Š
CBˆ]™\İÜ™Tİ\HH]ØZ]™YÚ[”Ú\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆ›ÜˆÛ˜\ÚİBˆ^XİYØÛÜNˆ[[™YØÛÜCBˆ
CBˆ]˜[œØXİ[ÛˆH™\İÜ™Tİ\˜[œØXİ[ÛƒBˆÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛˆH˜[œØXİ[ÛƒBˆ]™\İÜ™TØÛÜHH™\İÜ™Tİ\œØÛÜCBˆÛ˜\Úİœ›ÙÜ™\ÜÑ]HHÙ[‹›Y\™Ú[™Ñ]šXÙSØØ[›İšY\”™Y™\™[˜Ù\ÊBˆ[ÎˆÛ˜\Úİœ›ÙÜ™\ÜÑ]KBˆİ\œ™[ˆ›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Y™Ù]›ÙÜ™\ÜÑ]J
CBˆ
CBˆ]İÛœÕÜ]™[Ûİ\˜Ù\ÈH\Y\ÕÜ]™[Ûİ\˜ÙQ]JBˆÛ˜\ÚİBˆXİ]™T›Ùš[RQˆ™\İÜ™TØÛÜKœ›Ùš[RQBˆ
CBˆİX\™]ØZ]™\İÜ™TÚŞTİ™X[TÛ˜\Úİ[™ØZ]Y”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈÛ˜\ÚİœÚŞTİ™X[Hˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™J˜[œØXİ[ÛŠCBˆ™]\›ˆš[BˆCBˆİX\™]ØZ]™\İÜ™S]š[ÔÛ˜\ÚİY”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈÛ˜\Úİ›]š[ÔYÚ[œÈˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜKBˆ™\Ù\š[™Ñ]šXÙSØØ[ÛİYİ]NˆYCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™J˜[œØXİ[ÛŠCBˆ™]\›ˆš[BˆCBˆİX\™]Üİ\HH]ØZ]\P˜XÚİ\]RY”ØÛÜR\Ğİ\œ™[
BˆÛ˜\ÚİBˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÎˆYKBˆ™\Ù\š[™ÓYØXŞPÛİYYYXTİ]Nˆ™\Ù\™SYYXTİ]Q›ÜÛİYÚ]Bˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[ÛˆYKBˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™J˜[œØXİ[ÛŠCBˆ™]\›ˆš[BˆCBˆ]Üİ\TØÛÜHHÜİ\KœØÛÜCBƒBˆ]ØZ]ÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™Y˜Ø\\™TÛİ\˜ÙQY˜][Ôİ]JBˆ^XİYØÛÜQÙ[™\˜][ÛˆÜİ\TØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
CBƒBˆ]ØZ]™\Z\Xİ]™T›Ùš[TÚŞTİ™X[Tİ]RY“™YYY
BˆÛ˜\ÚİBˆ^XİYØÛÜNˆÜİ\TØÛÜCBˆ
CBˆİX\™]ØZ]™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆÜİ\TØÛÜKBˆÛ\˜]\Ò[™\™XY\”[[YNˆYCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™J˜[œØXİ[ÛŠCBˆ™]\›ˆš[BˆCBˆÛÛ\]TÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠ˜[œØXİ[ÛŠCBˆ™]\›ˆ^\š[Y[[ÛİY™\İÜ™T™\İ[
Bˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆÜİ\K˜]]Üš]]]™U˜XÚÙ\”›Ùš[RQÃBˆ
CBˆHØ]ÚÃBˆYˆ]Ú\™TÙ\šXÙ\Õ˜[œØXİ[ÛˆÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊ‘˜Z[YÈ™\İÜ™H^\š[Y[[PÛİYÛ˜\Úİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\NˆšPÛİYŠCBˆ™]\›ˆš[BˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜È^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
È]Nˆ]JHOˆ›ÛÛÃBˆİX\™]Øš™XİHOÈ”ÓÓ”Ù\šX[^˜][Û‹šœÛÛ“Øš™Xİ
Ú]ˆ]JH\ÏÈÔİš[™Îˆ[WKBˆ]™\œÚ[ÛˆHØš™XİÈ™\œÚ[Ûˆ—H\ÏÈİš[™È[ÙHÃBˆ™]\›ˆYCBˆCBˆ™]\›ˆÛÛ\\™TØÚ[XU™\œÚ[ÛŠ™\œÚ[Û‹Îˆ˜XÚİ\]K˜İ\œ™[ÛİYØÚ[XU™\œÚ[ÛŠHOH›Ü™\™Y\ØÙ[™[™ÃBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÛÛ\\™TØÚ[XU™\œÚ[ÛŠÈÎˆİš[™ËÈšÎˆİš[™ÊHOˆÛÛ\\š\ÛÛ”™\İ[ÃBˆ]YHËœÜ]
Ù\\˜]Üˆ‹ˆŠK›X\È[
	
HÏÈCBˆ]šYÚHšËœÜ]
Ù\\˜]Üˆ‹ˆŠK›X\È[
	
HÏÈCBˆ›Üˆ[™^[ˆ‹X^
Y˜Ûİ[šYÚ˜Ûİ[
HÃBˆ]Y˜[YHH[™^Y˜Ûİ[ÈYÚ[™^HˆBˆ]šYÚ˜[YHH[™^šYÚ˜Ûİ[ÈšYÚÚ[™^HˆBˆYˆY˜[YHšYÚ˜[YHÈ™]\›ˆ›Ü™\™Y\ØÙ[™[™ÈCBˆYˆY˜[YHˆšYÚ˜[YHÈ™]\›ˆ›Ü™\™Y\ØÙ[™[™ÈCBˆCBˆ™]\›ˆ›Ü™\™YØ[YCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈY\™Ú[™Ñ]šXÙSØØ[›İšY\”™Y™\™[˜Ù\ÊBˆ[È[˜ÛÛZ[™Îˆ›ÙÜ™\ÜÑ]KBˆİ\œ™[ˆ›ÙÜ™\ÜÑ]CBˆ
HOˆ›ÙÜ™\ÜÑ]HÃBˆ]İ\œ™[[İšY\ÈHXİ[Û˜\JBˆİ\œ™[›[İšYT›ÙÜ™\ÜË›X\È
	šY	
HKBˆ[š\]Z[™ÒÙ^\ÕÚ]ˆÈ^\İ[™ËØ[™Y]H[ƒBˆØ[™Y]K›\İ\]YH^\İ[™Ë›\İ\]YÈØ[™Y]Hˆ^\İ[™ÃBˆCBˆ
CBˆ]İ\œ™[\\ÛÙ\ÈHXİ[Û˜\JBˆİ\œ™[™\\ÛÙT›ÙÜ™\ÜË›X\È
	šY	
HKBˆ[š\]Z[™ÒÙ^\ÕÚ]ˆÈ^\İ[™ËØ[™Y]H[ƒBˆØ[™Y]K›\İ\]YH^\İ[™Ë›\İ\]YÈØ[™Y]Hˆ^\İ[™ÃBˆCBˆ
CBƒBˆ˜\ˆY\™ÙYH[˜ÛÛZ[™ÃBˆY\™ÙY›[İšYT›ÙÜ™\ÜÈH[˜ÛÛZ[™Ë›[İšYT›ÙÜ™\ÜË›X\È[H[ƒBˆİX\™]ØØ[Hİ\œ™[[İšY\ÖÙ[KšYH[ÙHÈ™]\›ˆ[HCBˆ˜\ˆ™\İ[H[CBˆ™\İ[›\İ™YˆHØØ[›\İ™YƒBˆ™\İ[›\İÛÛ[™Y™\™[˜ÙHHØØ[›\İÛÛ[™Y™\™[˜ÙCBˆ™\İ[›\İÙ\šXÙRYHØØ[›\İÙ\šXÙRYÏÈ[K›\İÙ\šXÙRYBˆ™\İ[›\İÛİ\˜ÙRYHØØ[›\İÛİ\˜ÙRYÏÈ[K›\İÛİ\˜ÙRYBˆ™]\›ˆ™\İ[BˆCBˆY\™ÙY™\\ÛÙT›ÙÜ™\ÜÈH[˜ÛÛZ[™Ë™\\ÛÙT›ÙÜ™\ÜË›X\È[H[ƒBˆİX\™]ØØ[Hİ\œ™[\\ÛÙ\ÖÙ[KšYH[ÙHÈ™]\›ˆ[HCBˆ˜\ˆ™\İ[H[CBˆ™\İ[›\İ™YˆHØØ[›\İ™YƒBˆ™\İ[›\İÛÛ[™Y™\™[˜ÙHHØØ[›\İÛÛ[™Y™\™[˜ÙCBˆ™\İ[›\İÙ\šXÙRYHØØ[›\İÙ\šXÙRYÏÈ[K›\İÙ\šXÙRYBˆ™\İ[›\İÛİ\˜ÙRYHØØ[›\İÛİ\˜ÙRYÏÈ[K›\İÛİ\˜ÙRYBˆ™]\›ˆ™\İ[BˆCBˆ™]\›ˆY\™ÙYBˆCBƒBˆš]˜]Hİ]XÈ]^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^HH™^\š[Y[[ÛİY™\İÜ™T[™[™ÕŒHƒBˆš]˜]Hİ]XÈ]^\š[Y[[ÛİY™\İÜ™T™XÛİ™\T™Yš^HÛİYŞ[˜Ô™\İÜ™T™XÛİ™\KˆƒBˆš]˜]Hİ]XÈ]^\š[Y[[ÛİY™\İÜ™T™XÛİ™\TİY™š^H‹šœÛÛˆƒBˆš]˜]Hİ]XÈ]^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\İY™š^H‹›İÛ™\‹šœÛÛˆƒBˆš]˜]Hİ]XÈ]^\š[Y[[ÛİY™\İÜ™U˜[œÜÜİY™š^H‹˜[œÜÜšœÛÛˆƒBˆš]˜]Hİ]XÈ]YØXŞQ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\Qš[[˜[YHHÛİYŞ[˜Ô™\İÜ™T™XÛİ™\KšœÛÛˆƒBˆš]˜]Hİ]XÈ]X^[][Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ]\ÈH
ˆWÌBˆš]˜]Hİ]XÈ]X^[][Q^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\]\ÈHMˆ
ˆWÌBˆš]˜]Hİ]XÈ]X^[][Q^\š[Y[[ÛİY™\İÜ™RY[]P]\ÈH
ˆWÌBƒBˆš]˜]H[[H^\š[Y[[ÛİY™\İÜ™SX[šY™\İØY™\İ[ÃBˆØ\ÙHZ\ÜÚ[™ÃBˆØ\ÙH[˜]˜Z[X›Jİš[™ÊCBˆØ\ÙH[˜[Y
İš[™ÊCBˆØ\ÙHØYY
^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İ
CBˆCBƒBˆš]˜]H[[HYØXŞQ^\š[Y[[ÛİY™\İÜ™SØY™\İ[ÃBˆØ\ÙHZ\ÜÚ[™ÃBˆØ\ÙH[˜]˜Z[X›Jİš[™ÊCBˆØ\ÙH[˜[Y
İš[™ÊCBˆØ\ÙHØYY
]JCBˆCBƒBˆš]˜]H[[H]]Üš^™YXØÛİ[›İ[™\T™\^Q\ÜÜÚ][ÛˆÃBˆØ\ÙHYÜ[™[™ÊÛİYŞ[˜Ô›İšY\ŠCBˆØ\ÙH[™XYPYÜY
ÛİYŞ[˜Ô›İšY\ŠCBˆØ\ÙHİ\\œÙYYÛÛ›™Xİ[ÛŠÛİYŞ[˜Ô›İšY\ŠCBˆØ\ÙH[˜]˜Z[X›CBˆØ\ÙH[˜[YBˆCBƒBˆš]˜]H˜\ˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QˆURQÃBˆš]˜]H˜\ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÎˆ\ÚÏ›ÚY™]™\ÃBƒBˆš]˜]Hİ]XÈ˜\ˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“ˆT“ÈÃBˆİX\™]\XØ][Û”İ\ÜHš[SX[˜YÙ\‹™Y˜][\›ÊBˆ›Üˆ˜\XØ][Û”İ\Ü\™XİÜKBˆ[ˆ\Ù\‘ÛXZ[“X\ÚÃBˆ
K™š\œİ[ÙHÈ™]\›ˆš[CBˆ]\™XİÜHH\XØ][Û”İ\Ü˜\[™[™Ô]ÛÛ\Û™[
‘XÛ\ÙH‹\Ñ\™XİÜNˆYJCBˆOÈš[SX[˜YÙ\‹™Y˜][˜Ü™X]Q\™XİÜJ]ˆ\™XİÜKÚ][\›YYX]Q\™XİÜšY\ÎˆYJCBˆ™]\›ˆ\™XİÜCBˆCBƒBˆš]˜]Hİ]XÈ˜\ˆYØXŞQ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“ˆT“ÈÃBˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“Ë˜\[™[™Ô]ÛÛ\Û™[
BˆYØXŞQ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\Qš[[˜[YCBˆ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“
˜[œØXİ[Û’QˆURQ
HOˆT“ÈÃBˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“Ë˜\[™[™Ô]ÛÛ\Û™[
Bˆ—
^\š[Y[[ÛİY™\İÜ™T™XÛİ™\T™Yš^
W
˜[œØXİ[Û’Q]ZYİš[™ÊW
^\š[Y[[ÛİY™\İÜ™T™XÛİ™\TİY™š^
HƒBˆ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\T“
˜[œØXİ[Û’QˆURQ
HOˆT“ÈÃBˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“Ë˜\[™[™Ô]ÛÛ\Û™[
Bˆ—
^\š[Y[[ÛİY™\İÜ™T™XÛİ™\T™Yš^
W
˜[œØXİ[Û’Q]ZYİš[™ÊW
^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\İY™š^
HƒBˆ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
˜[œØXİ[Û’QˆURQ
HOˆT“ÈÃBˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“Ë˜\[™[™Ô]ÛÛ\Û™[
Bˆ—
^\š[Y[[ÛİY™\İÜ™T™XÛİ™\T™Yš^
W
˜[œØXİ[Û’Q]ZYİš[™ÊW
^\š[Y[[ÛİY™\İÜ™U˜[œÜÜİY™š^
HƒBˆ
CBˆCBƒBˆš]˜]Hİ]XÈ˜\ˆ^\š[Y[[ÛİY™\İÜ™SX[šY™\İT“ˆT“ÈÃBˆ^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“ÃBˆ˜\[™[™Ô]ÛÛ\Û™[
ÛİYŞ[˜Ô™\İÜ™T™XÛİ™\K›X[šY™\İšœÛÛˆŠCBˆCBƒBˆš]˜]Hİ]XÈ[˜È\Õ˜[Y^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
BˆÈÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ›ÛÛÃBˆİX\™]›İšY\ˆHÛİYŞ[˜Ô›İšY\Š˜]Õ˜[YNˆÛÛ^œ›İšY\”˜]Õ˜[YJKBˆ›İšY\‹œ™\]Z\™\ĞXØÛİ[ÛÛ›™Xİ[Û‹BˆÛÛ^™Ù[™\˜][ÛˆHBˆ
ÛÛ^œ[™[™ÒY[]OË]˜Ûİ[ÏÈ
CBˆHX^[][Q^\š[Y[[ÛİY™\İÜ™RY[]P]\ËBˆÛÛ^›İ]ÛÚ[™Ô›Ùš[RQË˜Ûİ[H›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ËBˆÙ]
ÛÛ^›İ]ÛÚ[™Ô›Ùš[RQÊK˜Ûİ[BˆOHÛÛ^›İ]ÛÚ[™Ô›Ùš[RQË˜Ûİ[BˆÛÛ^œ™\İÜ™Y˜XÚÙ\”›Ùš[RQË˜Ûİ[H›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ËBˆÙ]
ÛÛ^œ™\İÜ™Y˜XÚÙ\”›Ùš[RQÊK˜Ûİ[BˆOHÛÛ^œ™\İÜ™Y˜XÚÙ\”›Ùš[RQË˜Ûİ[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ™]\›ˆYCBˆCBƒBˆš]˜]Hİ]XÈ[˜È^\š[Y[[ÛİY™\İÜ™P›İ[™\P]]Üš]SX]Ú\ÊBˆÈ™\\™Yˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^BˆÈÛÛ[Z][™Îˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ›ÛÛÃBˆ™\\™Yœ›İšY\”˜]Õ˜[YHOHÛÛ[Z][™Ëœ›İšY\”˜]Õ˜[YCBˆ	‰ˆ™\\™Y™Ù[™\˜][ÛˆOHÛÛ[Z][™Ë™Ù[™\˜][ÛƒBˆ	‰ˆ™\\™Yœ[™[™ÒY[]HOHÛÛ[Z][™Ëœ[™[™ÒY[]CBˆ	‰ˆ™\\™Y›İ]ÛÚ[™Ô›Ùš[RQÈOHÛÛ[Z][™Ë›İ]ÛÚ[™Ô›Ùš[RQÃBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]\›ˆT“BˆX^[][P]\Îˆ[Bˆ
H›İÜÈOˆ]HÃBˆ]˜[Y\ÈHH\›œ™\Ûİ\˜ÙU˜[Y\Ê›Ü’Ù^\ÎˆËš\Ô™Yİ[\‘š[RÙ^WJCBˆİX\™˜[Y\Ëš\Ô™Yİ[\‘š[HOHYH[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[T™XYÛÜœ\š[JCBˆCBˆ][™HHHš[R[™J›Ü”™XY[™Ñœ›ÛNˆ\›
CBˆY™\ˆÈ[™K˜ÛÜÙQš[J
HCBˆ]]HH[™Kœ™XY]JÙ“[™İˆX^[][P]\È
ÈJCBˆİX\™]K˜Ûİ[HX^[][P]\È[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[T™XYÛÜœ\š[JCBˆCBˆ™]\›ˆ]CBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

CBˆOˆ^\š[Y[[ÛİY™\İÜ™SX[šY™\İØY™\İ[ÃBˆİX\™]\›H^\š[Y[[ÛİY™\İÜ™SX[šY™\İT“[ÙHÃBˆ™]\›ˆ[˜]˜Z[X›J\XØ][Ûˆİ\Ü\È[˜]˜Z[X›HŠCBˆCBˆİX\™š[SX[˜YÙ\‹™Y˜][™š[Q^\İÊ]]ˆ\›œ]
H[ÙHÃBˆ™]\›ˆ›Z\ÜÚ[™ÃBˆCBˆ]]Nˆ]CBˆÈÃBˆ]HHH›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆ\›BˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ]\ÃBˆ
CBˆHØ]ÚÃBˆ™]\›ˆ[˜]˜Z[X›Jİš[™Ê™Y›Xİ[™Îˆ\JÙˆ\œ›ÜŠJJCBˆCBˆ]X[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆÈÃBˆX[šY™\İHH”ÓÓ‘XÛÙ\Š
K™XÛÙJBˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İœÙ[‹Bˆœ›ÛNˆ]CBˆ
CBˆHØ]ÚÃBˆ™]\›ˆš[˜[Y
›X[šY™\İXÛÙH˜Z[YŠCBˆCBˆİX\™X[šY™\İœØÚ[XU™\œÚ[ÛˆOHˆ[ÙHÃBˆ™]\›ˆš[˜[Y
[œİ\ÜYX[šY™\İØÚ[XHŠCBˆCBˆİÚ]Ú
X[šY™\İœ™XÛİ™\RÚ[™X[šY™\İ˜XØÛİ[›İ[™\PÛÛ^
HÃBˆØ\ÙH
›Ü™[˜\PÛİY™\İÜ™Kš[
NƒBˆİX\™[X[šY™\İš\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\H[ÙHÃBˆ™]\›ˆš[˜[Y
›Ü™[˜\H™XÛİ™\HÛZ[YYHØ[›ÛšXØ[ÚYXØ\ˆŠCBˆCBˆØ\ÙH
˜XØÛİ[›İ[™\KœÛÛYJ]ÛÛ^
JNƒBˆİX\™\Õ˜[Y^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
ÛÛ^
H[ÙHÃBˆ™]\›ˆš[˜[Y
˜XØÛİ[X›İ[™\HÛÛ^\È[˜[YŠCBˆCBˆØ\ÙH
›Ü™[˜\PÛİY™\İÜ™KœÛÛYJK
˜XØÛİ[›İ[™\Kš[
NƒBˆ™]\›ˆš[˜[Y
›X[šY™\İÚ[™[™ÛÛ^\ØYÜ™YHŠCBˆCBˆİX\™[X[šY™\İš\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\CBˆX[šY™\İš\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Ûˆ[ÙHÃBˆ™]\›ˆš[˜[Y
˜Ø[›ÛšXØ[™XÛİ™\H\ÈZ\ÜÚ[™È]ÈYYXK\İ]H˜[œØXİ[ÛˆŠCBˆCBˆYˆX[šY™\İœ™XÛİ™\RÚ[™OH˜XØÛİ[›İ[™\KBˆX[šY™\İš\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HOHX[šY™\İš\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[ÛˆÃBˆ™]\›ˆš[˜[Y
˜XØÛİ[X›İ[™\HYYXK\İ]H›YÜÈ\ØYÜ™YHŠCBˆCBˆYˆX[šY™\İœİ]HOH˜ÛÛ[Z]]]Üš^™YBˆX[šY™\İœ™XÛİ™\RÚ[™OH˜XØÛİ[›İ[™\HÃBˆ™]\›ˆš[˜[Y
›Ü™[˜\H™XÛİ™\HØ[››İ]]Üš^™H[ˆXØÛİ[X›İ[™\HÛÛ[Z]ŠCBˆCBˆ]\ÒÙY\ØØ[]PÛİ[HX[šY™\İšÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[OHš[Bˆ]\ÒÙY\ØØ[YÙ\İHX[šY™\İšÙY\ØØ[˜[œÜÜ^[ØYÒLMˆOHš[BˆİX\™\ÒÙY\ØØ[]PÛİ[OH\ÒÙY\ØØ[YÙ\İ[ÙHÃBˆ™]\›ˆš[˜[Y
šÙY\[ØØ[^[ØYİÛ™\œÚ\\È[˜ÛÛ\]HŠCBˆCBˆYˆ]]PÛİ[HX[šY™\İšÙY\ØØ[˜[œÜÜ^[ØY]PÛİ[ÃBˆİX\™X[šY™\İœ™XÛİ™\RÚ[™OH˜XØÛİ[›İ[™\KBˆ]PÛİ[ˆBˆ]PÛİ[HX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ËBˆ]YÙ\İHX[šY™\İšÙY\ØØ[˜[œÜÜ^[ØYÒLM‹BˆYÙ\İ]˜Ûİ[HLBˆX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^Ë›İ]ÛÚ[™Ô›Ùš[RQËš\Ñ[\HOHYH[ÙHÃBˆ™]\›ˆš[˜[Y
šÙY\[ØØ[^[ØYİÛ™\œÚ\\È[˜[YŠCBˆCBˆCBˆYˆX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™YBˆ[X[šY™\İš\ÒÙY\ØØ[˜[œÜÜ^[ØYÃBˆ™]\›ˆš[˜[Y
˜]]Üš^™YÙY\[ØØ[™XÛİ™\H\È›È˜[œÜÜ^[ØYŠCBˆCBˆ™]\›ˆ›ØYY
X[šY™\İ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È]]Üš^™Y™\^Q\ÜÜÚ][ÛŠBˆ›ÜˆÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ]]Üš^™YXØÛİ[›İ[™\T™\^Q\ÜÜÚ][ÛˆÃBˆİX\™]›İšY\ˆHÛİYŞ[˜Ô›İšY\Š˜]Õ˜[YNˆÛÛ^œ›İšY\”˜]Õ˜[YJKBˆ›İšY\‹œ™\]Z\™\ĞXØÛİ[ÛÛ›™Xİ[Ûˆ[ÙHÃBˆ™]\›ˆš[˜[YBˆCBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™Bˆ]İ\œ™[Ù[™\˜][ÛˆHY˜][Ëš[YÙ\Š›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Ù[™\˜][Û’Ù^JCBˆYˆİ\œ™[Ù[™\˜][ÛˆˆÛÛ^™Ù[™\˜][ÛˆÃBˆ™]\›ˆœİ\\œÙYYÛÛ›™Xİ[ÛŠ›İšY\ŠCBˆCBˆİX\™İ\œ™[Ù[™\˜][ÛˆOHÛÛ^™Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆš[˜[YBˆCBƒBˆ]›İ[™\R\Ô[™[™ÈHY˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[›İ[™\T[™[™ÒÙ^JCBˆ]\šÙYY[]HHY˜][Ëœİš[™Ê›Ü’Ù^Nˆ›İšY\‹œ[™[™ĞXØÛİ[Y[]RÙ^JCBˆ]İ\œ™[Y[]HHY˜][Ëœİš[™Ê›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]RÙ^JCBˆ]Y[]R\Õ[œ™\ÛÛ™YHY˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]U[œ™\ÛÛ™YÙ^JCBˆ]\Ñ[PYÜYˆ›ÛÛBˆYˆ][™[™ÒY[]HHÛÛ^œ[™[™ÒY[]HÃBˆ\Ñ[PYÜYHX›İ[™\R\Ô[™[™ÃBˆ	‰ˆ\šÙYY[]HOHš[Bˆ	‰ˆİ\œ™[Y[]HOH[™[™ÒY[]CBˆ	‰ˆZY[]R\Õ[œ™\ÛÛ™YBˆH[ÙHÃBˆ\Ñ[PYÜYHX›İ[™\R\Ô[™[™ÃBˆ	‰ˆ\šÙYY[]HOHš[Bˆ	‰ˆY[]R\Õ[œ™\ÛÛ™YBˆCBˆYˆ\Ñ[PYÜYÃBˆ™]\›ˆ˜[™XYPYÜY
›İšY\ŠCBˆCBƒBˆ]\ÓX]Ú[™Ô[™[™Ñ]šY[˜ÙNˆ›ÛÛBˆYˆ][™[™ÒY[]HHÛÛ^œ[™[™ÒY[]HÃBˆ\ÓX]Ú[™Ô[™[™Ñ]šY[˜ÙHH\šÙYY[]HOH[™[™ÒY[]CBˆİ\œ™[Y[]HOH[™[™ÒY[]CBˆH[ÙHÃBˆ\ÓX]Ú[™Ô[™[™Ñ]šY[˜ÙHH›İ[™\R\Ô[™[™ÈY[]R\Õ[œ™\ÛÛ™YBˆCBˆİX\™
\šÙYY[]HOHš[\šÙYY[]HOHÛÛ^œ[™[™ÒY[]JKBˆ\ÓX]Ú[™Ô[™[™Ñ]šY[˜ÙH[ÙHÃBˆ™]\›ˆš[˜[YBˆCBƒBˆİX\™RP\XØ][Û‹œÚ\™Yš\Ô›İXİY]P]˜Z[X›H[ÙHÃBˆ™]\›ˆ[˜]˜Z[X›CBˆCBˆİX\™ÛİYŞ[˜ÕÚÙ[”İÜ™Kš\ÕÚÙ[Š›Üˆ›İšY\ŠH[ÙHÃBˆ™]\›ˆš[˜[YBˆCBˆ™]\›ˆ˜YÜ[™[™Ê›İšY\ŠCBˆCBƒBˆİ]XÈ[˜ÈXØÛİ[›İ[™\U˜XÚÙ\ÛX[\]]Üš]J
CBˆOˆ^\š[Y[[ÛİY˜XÚÙ\ÛX[\]]Üš]HÃBˆİÚ]ÚØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

HÃBˆØ\ÙH›Z\ÜÚ[™ÎƒBƒBˆ™]\›ˆ\Ù\‘Y˜][Ëœİ[™\™˜›ÛÛ
Bˆ›Ü’Ù^Nˆ^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^CBˆ
HÈ˜›ØÚÙYˆ››Û™CBˆØ\ÙH[˜]˜Z[X›Kš[˜[YƒBƒBˆ™]\›ˆ˜›ØÚÙYBˆØ\ÙH›ØYY
]X[šY™\İ
NƒBˆİÚ]ÚX[šY™\İœİ]HÃBˆØ\ÙHœ™\\š[™Ë˜ÛÛ\]YƒBˆ™]\›ˆ››Û™CBˆØ\ÙHœ™\\™YƒBƒBˆ™]\›ˆX[šY™\İš\ÒÙY\ØØ[˜[œÜÜ^[ØYÈ››Û™Hˆ˜›ØÚÙYBˆØ\ÙHšÙY\ØØ[Üš]P]]Üš^™YƒBˆ™]\›ˆ››Û™CBˆØ\ÙH˜ÛÛ[Z]]]Üš^™YƒBˆœ™XZÃBˆCBˆİX\™]ÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^[ÙHÃBˆ™]\›ˆ˜›ØÚÙYBˆCBƒBˆ™]\›ˆ˜]]Üš^™Y
ÛÛ^
CBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØYYØXŞQ^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ

CBˆOˆYØXŞQ^\š[Y[[ÛİY™\İÜ™SØY™\İ[ÃBˆİX\™]\›HYØXŞQ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“[ÙHÃBˆ™]\›ˆ[˜]˜Z[X›J\XØ][Ûˆİ\Ü\È[˜]˜Z[X›HŠCBˆCBˆİX\™š[SX[˜YÙ\‹™Y˜][™š[Q^\İÊ]]ˆ\›œ]
H[ÙHÃBˆ™]\›ˆ›Z\ÜÚ[™ÃBˆCBˆÈÃBˆ]˜[Y\ÈHH\›œ™\Ûİ\˜ÙU˜[Y\Ê›Ü’Ù^\ÎˆËš\Ô™Yİ[\‘š[RÙ^K™š[TÚ^™RÙ^WJCBˆİX\™˜[Y\Ëš\Ô™Yİ[\‘š[HOHYH[ÙHÃBˆ™]\›ˆš[˜[Y
›YØXŞH™XÛİ™\H\È›İH™Yİ[\ˆš[HŠCBˆCBˆYˆ]š[TÚ^™HH˜[Y\Ë™š[TÚ^™KBˆš[TÚ^™HˆX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÈÃBˆ™]\›ˆš[˜[Y
›YØXŞH™XÛİ™\H^ÙYYÈHÛİYÛ˜\Úİ[Z]ŠCBˆCBˆ]]HHH›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆ\›BˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÃBˆ
CBˆİX\™^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
]JH[ÙHÃBˆ™]\›ˆš[˜[Y
›YØXŞH™XÛİ™\H\Ù\È[ˆ[œİ\ÜYØÚ[XHŠCBˆCBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ]XÛÙYHHXÛÙ\‹™XÛÙJ˜XÚİ\]KœÙ[‹œ›ÛNˆ]JCBƒBˆ]ØY™TÛ˜\ÚİHXÛÙYœ™YXİY›Ü‘^\š[Y[[ÛİYŞ[˜Ê
CBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœÛÜYÙ^\×CBˆ]ØY™Q]HHH[˜ÛÙ\‹™[˜ÛÙJØY™TÛ˜\Úİ
CBˆİX\™ØY™Q]K˜Ûİ[HX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\È[ÙHÃBˆ™]\›ˆš[˜[Y
œØ[š]^™YYØXŞH™XÛİ™\H^ÙYYÈHÛİYÛ˜\Úİ[Z]ŠCBˆCBˆ™]\›ˆ›ØYY
ØY™Q]JCBˆHØ]Ú]\œ›Üˆ\ÈÛØÛØQ\œ›ÜˆÚ\™H\œ›Ü‹˜ÛÙHOH™š[T™XY›Ô\›Z\ÜÚ[ÛˆÃBˆ™]\›ˆ[˜]˜Z[X›Jœ›İXİY]H\È[˜]˜Z[X›HŠCBˆHØ]ÚÃBˆ™]\›ˆš[˜[Y
›YØXŞH™XÛİ™\H˜[Y][Ûˆ˜Z[YŠCBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÜš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
BˆÈX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
H›İÜÈÃBˆİX\™]\›H^\š[Y[[ÛİY™\İÜ™SX[šY™\İT“[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[S›ÔİXÚš[JCBˆCBˆ]]HHH”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJX[šY™\İ
CBˆİX\™]K˜Ûİ[HX^[][Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ]\È[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[UÜš]Sİ]Ù”ÜXÙJCBˆCBˆH]KÜš]JÎˆ\›Ü[ÛœÎˆË˜]ÛZXË˜ÛÛ\]Qš[T›İXİ[Û—JCBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ
Bˆ›ÜˆX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HOˆ
\›ˆT“]Nˆ]JOÈÃBˆİX\™]\›H^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
KBˆ]İÛ™\œÚ\T“H^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\T“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
KBˆ]]HHOÈ›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆ\›BƒBˆX^[][P]\ÎˆX^[][SX[X[˜XÚİ\š[P]\ÃBˆ
KBˆ]İÛ™\œÚ\]HHOÈ›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆİÛ™\œÚ\T“BˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\]\ÃBˆ
KBˆ]İÛ™\œÚ\HOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJBˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SİÛ™\œÚ\œÙ[‹Bˆœ›ÛNˆİÛ™\œÚ\]CBˆ
KBˆİÛ™\œÚ\˜[Y]\ÊBˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ™XÛİ™\RÚ[™ˆX[šY™\İœ™XÛİ™\RÚ[™Bˆ^[ØYˆ]CBˆ
H[ÙHÃBˆ™]\›ˆš[BˆCBˆ™]\›ˆ
\›]JCBˆCBƒBˆš]˜]Hİ]XÈ[˜È›Ü›X[^™YÙY\ØØ[˜[œÜÜ^[ØY
œ›ÛH]Nˆ]JH›İÜÈOˆ]HÃBˆİX\™Y]Kš\Ñ[\KBˆ]K˜Ûİ[HX^[][SX[X[˜XÚİ\š[P]\ËBˆ^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
]JH[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[T™XYÛÜœ\š[JCBˆCBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ]XÛÙYHHXÛÙ\‹™XÛÙJ˜XÚİ\]KœÙ[‹œ›ÛNˆ]JCBˆ]ØY™TÛ˜\ÚİHXÛÙYœ™YXİY›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆİš\ÚŞTİ™X[P\˜Ú]™\ÎˆYCBˆ
CBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœ™]Tš[YœÛÜYÙ^\×CBˆ]ØY™Q]HHH[˜ÛÙ\‹™[˜ÛÙJØY™TÛ˜\Úİ
CBˆİX\™\ØY™Q]Kš\Ñ[\KBˆØY™Q]K˜Ûİ[HX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\È[ÙHÃBˆ›İÈ›İ[™YT“Ù\ÜÚ[Û‘\œ›Ü‹œ™\ÜÛœÙUÛÓ\™ÙJBˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÃBˆ
CBˆCBˆ™]\›ˆØY™Q]CBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™ÙY\ØØ[˜[œÜÜ^[ØY
Bˆ›ÜˆX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HOˆ]OÈÃBˆİX\™X[šY™\İš\ÒÙY\ØØ[˜[œÜÜ^[ØYBˆ]\›H^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
KBˆ]]HHOÈ›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆ\›BˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİYÛ˜\Úİ]\ÃBˆ
KBˆX[šY™\İ˜[Y]\ÒÙY\ØØ[˜[œÜÜ^[ØY
]JKBˆ^\š[Y[[ÛİYÛ˜\ÚİØÚ[XR\Ôİ\ÜY
]JH[ÙHÃBˆ™]\›ˆš[BˆCBˆ™]\›ˆ]CBˆCBƒBˆXZ[XİÜƒBˆ[˜È]]Üš^™Y^\š[Y[[ÛİYÙY\ØØ[™\^J
CBˆOˆ^\š[Y[[ÛİYÙY\ØØ[™\^OÈÃBˆİX\™Ø\ÙH›ØYY
]X[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™YBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆ]ÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^Bˆ]]HHÙ[‹˜›İ[™ÙY\ØØ[˜[œÜÜ^[ØY
›ÜˆX[šY™\İ
KBˆ]›Ûİš[H^\š[Y[[ÛİYÛ˜\Úİ›Ûİš[
œ›ÛNˆ]JH[ÙHÃBˆ™]\›ˆš[BˆCBˆ™]\›ˆ^\š[Y[[ÛİYÙY\ØØ[™\^JBˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆÛÛ^ˆÛÛ^BˆÛ˜\Úİˆ^\š[Y[[ÛİYÛ˜\Úİ
]Nˆ]K›Ûİš[ˆ›Ûİš[
CBˆ
CBˆCBƒBˆXZ[XİÜƒBˆ[˜È™Xš[™]]Üš^™Y^\š[Y[[ÛİYÙY\ØØ[™\^JBˆ›İšY\”˜]Õ˜[YNˆİš[™ËBˆÙ[™\˜][Ûˆ[Bˆ™\šYšYY[™[™ÒY[]Nˆİš[™ÃBˆ
HOˆ^\š[Y[[ÛİYÙY\ØØ[™\^OÈÃBˆİX\™]™\šYšYY[™[™ÒY[]Kš\Ñ[\KBˆ™\šYšYY[™[™ÒY[]K]˜Ûİ[BˆHÙ[‹›X^[][Q^\š[Y[[ÛİY™\İÜ™RY[]P]\ËBˆØ\ÙH›ØYY
˜\ˆX[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™YBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆ]™]š[İ\ĞÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^Bˆ™]š[İ\ĞÛÛ^œ›İšY\”˜]Õ˜[YHOH›İšY\”˜]Õ˜[YKBˆ™]š[İ\ĞÛÛ^œ[™[™ÒY[]HOH™\šYšYY[™[™ÒY[]KBˆ™]š[İ\ĞÛÛ^›İ]ÛÚ[™Ô›Ùš[RQËš\Ñ[\KBˆÙ[™\˜][ÛˆH™]š[İ\ĞÛÛ^™Ù[™\˜][Û‹Bˆ]›İšY\ˆHÛİYŞ[˜Ô›İšY\Š˜]Õ˜[YNˆ›İšY\”˜]Õ˜[YJKBˆ›İšY\‹œ™\]Z\™\ĞXØÛİ[ÛÛ›™Xİ[Û‹BˆÙ[‹˜›İ[™ÙY\ØØ[˜[œÜÜ^[ØY
›ÜˆX[šY™\İ
HOHš[[ÙHÃBˆ™]\›ˆš[BˆCBƒBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™BˆİX\™Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[›İ[™\T[™[™ÒÙ^JKBˆY˜][Ëš[YÙ\Š›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Ù[™\˜][Û’Ù^JHOHÙ[™\˜][Û‹BˆY˜][Ëœİš[™Ê›Ü’Ù^Nˆ›İšY\‹œ[™[™ĞXØÛİ[Y[]RÙ^JCBˆOH™\šYšYY[™[™ÒY[]KBˆÛİYŞ[˜ÕÚÙ[”İÜ™Kš\ÕÚÙ[Š›Üˆ›İšY\ŠKBˆY˜][ËœŞ[˜Ú›Ûš^™J
H[ÙHÃBˆ™]\›ˆš[BˆCBƒBˆ]™X›İ[™ÛÛ^H^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
Bˆ›İšY\”˜]Õ˜[YNˆ›İšY\”˜]Õ˜[YKBˆÙ[™\˜][ÛˆÙ[™\˜][Û‹Bˆ[™[™ÒY[]Nˆ™\šYšYY[™[™ÒY[]KBˆİ]ÛÚ[™Ô›Ùš[RQÎˆ×CBˆ
CBˆİX\™Ù[‹š\Õ˜[Y^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
™X›İ[™ÛÛ^
H[ÙHÃBˆ™]\›ˆš[BˆCBˆYˆX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^OH™X›İ[™ÛÛ^ÃBˆX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^H™X›İ[™ÛÛ^BˆÈÃBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ™Xš[™ÙY\[ØØ[™XÛİ™\HÈH™\šYšYYXØÛİ[ÛÛ›™Xİ[Ûˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆš[BˆCBˆCBˆ™]\›ˆ]]Üš^™Y^\š[Y[[ÛİYÙY\ØØ[™\^J
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È›İ[™^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\\Õ˜[Y›ÜÛX[\
BˆÈX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HOˆ›ÛÛÃBˆİX\™]™XÛİ™\UT“H^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
KBˆ]İÛ™\œÚ\T“H^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\T“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]š[SX[˜YÙ\ˆHš[SX[˜YÙ\‹™Y˜][Bˆ]Û˜\Úİ^\İÈHš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆ™XÛİ™\UT“œ]
CBˆ]İÛ™\œÚ\^\İÈHš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆİÛ™\œÚ\T“œ]
CBˆYˆÛ˜\Úİ^\İËBˆ›İ[™^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ
›ÜˆX[šY™\İ
HOHš[ÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆX[šY™\İš\ÒÙY\ØØ[˜[œÜÜ^[ØYBˆ]˜[œÜÜT“H^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
Bˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
KBˆš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆ˜[œÜÜT“œ]
KBˆ›İ[™ÙY\ØØ[˜[œÜÜ^[ØY
›ÜˆX[šY™\İ
HOHš[ÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆÛ˜\Úİ^\İÈÃBˆ™]\›ˆYCBˆCBˆİX\™İÛ™\œÚ\^\İÈ[ÙHÈ™]\›ˆYHCBˆİX\™]İÛ™\œÚ\]HHOÈ›İ[™Y^\š[Y[[ÛİY™\İÜ™Q]JBˆ]ˆİÛ™\œÚ\T“BˆX^[][P]\ÎˆX^[][Q^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\]\ÃBˆ
KBˆ]İÛ™\œÚ\HOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJBˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SİÛ™\œÚ\œÙ[‹Bˆœ›ÛNˆİÛ™\œÚ\]CBˆ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ™]\›ˆİÛ™\œÚ\œØÚ[XU™\œÚ[ÛˆOHCBˆ	‰ˆİÛ™\œÚ\˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆ	‰ˆİÛ™\œÚ\œ™XÛİ™\RÚ[™OHX[šY™\İœ™XÛİ™\RÚ[™BˆCBƒBˆXZ[XİÜƒBˆ[˜È™\\™Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\JBˆ\Ú[™ÈÛ˜\Úİˆ^\š[Y[[ÛİYÛ˜\ÚİBˆXØÛİ[›İ[™\PÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^ÈHš[BˆÙY\ØØ[˜[œÜÜÛ˜\Úİˆ^\š[Y[[ÛİYÛ˜\ÚİÈHš[Bˆ
HOˆ›ÛÛÃBˆİX\™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈOHš[BˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHš[[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™Y\ÙYÈİ™\Üš]H[ˆ[™š[š\ÚYÛİY™\İÜ™H˜[œØXİ[Ûˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBƒBˆİÚ]ÚÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

HÃBˆØ\ÙH›ØYY
]X[šY™\İ
HÚ\™HX[šY™\İœİ]HOH˜ÛÛ\]YƒBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QHX[šY™\İ˜[œØXİ[Û’QBˆİX\™\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
KBˆÛX[\^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ›ÜˆX[šY™\İ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆØ\ÙH›Z\ÜÚ[™ÎƒBˆİX\™U\Ù\‘Y˜][Ëœİ[™\™˜›ÛÛ
›Ü’Ù^NˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^JKBˆÛX[\Üœ[™Y^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™Y\ÙYÈ™\XÙHHÛİY™\İÜ™HÚÜÙHX[šY™\İ\ÈZ\ÜÚ[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆØ\ÙH›ØYY[˜]˜Z[X›Kš[˜[YƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™Y\ÙYÈİ™\Üš]H[ˆ[™š[š\ÚYÜˆ[œ™XYX›HÛİY™\İÜ™H˜[œØXİ[Ûˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBƒBˆ]ÙY\ØØ[˜[œÜÜ^[ØYˆ]OÃBˆÈÃBˆÙY\ØØ[˜[œÜÜ^[ØYHHÙY\ØØ[˜[œÜÜÛ˜\Úİ›X\ÃBˆHÙ[‹››Ü›X[^™YÙY\ØØ[˜[œÜÜ^[ØY
œ›ÛNˆ	™]JCBˆCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™Y\ÙY[ˆ[˜[YÙY\[ØØ[˜[œÜÜ™XÛİ™\H^[ØYˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBƒBˆ]˜[œØXİ[Û’QHURQ

CBˆİX\™]\›HÙ[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“
˜[œØXİ[Û’Qˆ˜[œØXİ[Û’Q
KBˆ]İÛ™\œÚ\T“HÙ[‹™^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\T“
Bˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆ
KBˆÙY\ØØ[˜[œÜÜ^[ØYOHš[BˆÙ[‹™^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
˜[œØXİ[Û’Qˆ˜[œØXİ[Û’Q
HOHš[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]™XÛİ™\RÚ[™ˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\RÚ[™HXØÛİ[›İ[™\PÛÛ^OHš[BˆÈ›Ü™[˜\PÛİY™\İÜ™CBˆˆ˜XØÛİ[›İ[™\CBˆİX\™Û˜\Úİ™]K˜Ûİ[HÙ[‹›X^[][SX[X[˜XÚİ\š[P]\ËBˆXØÛİ[›İ[™\PÛÛ^›X\
Ù[‹š\Õ˜[Y^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
CBˆÏÈYKBˆÙY\ØØ[˜[œÜÜ^[ØYOHš[Bˆ
XØÛİ[›İ[™\PÛÛ^Ë›İ]ÛÚ[™Ô›Ùš[RQËš\Ñ[\HOHYJH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™Y\ÙY[ˆİ™\œÚ^™YÜˆ[˜[YÛİY™\İÜ™H™XÛİ™\HÚ[‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBƒBˆ˜\ˆ[[™ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HH˜[ÙCBˆ˜\ˆ[[™ÓYYXTİ]T™XÛİ™\HH˜[ÙCBˆÚYˆÜÊSÔÊCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆ[[™ÓYYXTİ]T™XÛİ™\HHYCBˆ[[™ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HHXØÛİ[›İ[™\PÛÛ^OHš[BˆCBˆÙ[ÙCBˆİX\™XØÛİ[›İ[™\PÛÛ^OHš[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[™YƒBˆ˜\ˆX[šY™\İH^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İ
Bˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆİ]Nˆœ™\\š[™ËBˆXØÛİ[›İ[™\PÛÛ^ˆXØÛİ[›İ[™\PÛÛ^Bˆ\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\Nˆ[[™ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\KBˆ\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Ûˆ[[™ÓYYXTİ]T™XÛİ™\KBˆÙY\ØØ[˜[œÜÜ^[ØYˆÙY\ØØ[˜[œÜÜ^[ØYBˆ
CBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QH˜[œØXİ[Û’QBˆ˜\ˆX[šY™\İØ\Ô\œÚ\İYH˜[ÙCBˆ˜\ˆYYXTİ]T™XÛİ™\UØ\Ğ][\YH˜[ÙCBˆÈÃBˆHÛ˜\Úİ™]KÜš]JÎˆ\›Ü[ÛœÎˆË˜]ÛZXË˜ÛÛ\]Qš[T›İXİ[Û—JCBˆ]İÛ™\œÚ\H^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SİÛ™\œÚ\
Bˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆ™XÛİ™\RÚ[™ˆ™XÛİ™\RÚ[™Bˆ^[ØYˆÛ˜\Úİ™]CBˆ
CBˆ]İÛ™\œÚ\]HHH”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJİÛ™\œÚ\
CBˆHİÛ™\œÚ\]KÜš]JBˆÎˆİÛ™\œÚ\T“BˆÜ[ÛœÎˆË˜]ÛZXË˜ÛÛ\]Qš[T›İXİ[Û—CBˆ
CBˆYˆ]ÙY\ØØ[˜[œÜÜ^[ØYBˆ]˜[œÜÜT“HÙ[‹™^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
Bˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆ
HÃBˆHÙY\ØØ[˜[œÜÜ^[ØYÜš]JBˆÎˆ˜[œÜÜT“BˆÜ[ÛœÎˆË˜]ÛZXË˜ÛÛ\]Qš[T›İXİ[Û—CBˆ
CBˆCBƒBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆX[šY™\İØ\Ô\œÚ\İYHYCBˆ\Ù\‘Y˜][Ëœİ[™\™œÙ]
YK›Ü’Ù^NˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^JCBˆİX\™\Ù\‘Y˜][Ëœİ[™\™œŞ[˜Ú›Ûš^™J
H[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[UÜš]U[šÛ›İÛŠCBˆCBˆÚYˆÜÊSÔÊCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆYYXTİ]T™XÛİ™\UØ\Ğ][\YHYCBˆYˆXØÛİ[›İ[™\PÛÛ^OHš[ÃBˆİX\™YYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆœ™\\™T™[[İPXØÛİ[›İ[™\P\˜Ú]™T™XÛİ™\J˜[œØXİ[Û’Qˆ˜[œØXİ[Û’Q
H[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[UÜš]U[šÛ›İÛŠCBˆCBˆH[ÙHÃBˆİX\™YYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆœİ\Ü[™YYXTİ]TŞ[˜Ñ›Ü”™\\™Y™XÛİ™\J˜[œØXİ[Û’Qˆ˜[œØXİ[Û’Q
H[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ™š[UÜš]U[šÛ›İÛŠCBˆCBˆCBˆCBˆÙ[™YƒBˆX[šY™\İœİ]HHœ™\\™YBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆ™]\›ˆYCBˆHØ]ÚÃBƒBˆ˜\ˆYYXTİ]T™[X\ÙTİXØÙYYYHZ[[™ÓYYXTİ]T™XÛİ™\CBˆÚYˆÜÊSÔÊCBˆYˆYYXTİ]T™XÛİ™\UØ\Ğ][\YØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆYˆ[[™ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HÃBˆYYXTİ]T™[X\ÙTİXØÙYYYHYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆ˜ÛÛ\]T™[[İPXØÛİ[›İ[™\P\˜Ú]™T™XÛİ™\JBˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆ
CBˆH[ÙHÃBˆYYXTİ]T™[X\ÙTİXØÙYYYHYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆ˜ÛÛ\]SYYXTİ]TŞ[˜Ô™\\™Y™XÛİ™\J˜[œØXİ[Û’Qˆ˜[œØXİ[Û’Q
CBˆCBˆCBˆÙ[™YƒBˆYˆX[šY™\İØ\Ô\œÚ\İYÃBƒBˆÈH\ØØ\™™\\š[™Ñ^\š[Y[[ÛİY™\İÜ™JBˆX[šY™\İBˆYYXTİ]T™[X\ÙP[™XYTİXØÙYYYˆYYXTİ]T™[X\ÙTİXØÙYYYBˆ
CBˆH[ÙHÃBˆOÈš[SX[˜YÙ\‹™Y˜][œ™[[İ™R][J]ˆ\›
CBˆOÈš[SX[˜YÙ\‹™Y˜][œ™[[İ™R][J]ˆİÛ™\œÚ\T“
CBˆYˆ]˜[œÜÜT“HÙ[‹™^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
Bˆ˜[œØXİ[Û’Qˆ˜[œØXİ[Û’QBˆ
HÃBˆOÈš[SX[˜YÙ\‹™Y˜][œ™[[İ™R][J]ˆ˜[œÜÜT“
CBˆCBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QHš[BˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ\œÚ\İÛİY™\İÜ™H™XÛİ™\HÛ˜\Úİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È\ØØ\™™\\š[™Ñ^\š[Y[[ÛİY™\İÜ™JBˆÈX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆYYXTİ]T™[X\ÙP[™XYTİXØÙYYYˆ›ÛÛH˜[ÙCBˆ
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
˜\ˆİ\œ™[
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆİ\œ™[˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆİ\œ™[œİ]HOHœ™\\š[™ËBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHİ\œ™[˜[œØXİ[Û’Q[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆİ\œ™[š\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Û‹Bˆ[YYXTİ]T™[X\ÙP[™XYTİXØÙYYYBˆ\™[X\ÙSYYXTİ]T™XÛİ™\U˜[œØXİ[ÛŠ›Üˆİ\œ™[
HÃBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆİ\œ™[œİ]HH˜ÛÛ\]YBˆÈÃBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
İ\œ™[
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İX˜[™Ûˆ[ˆ[˜ÛÛ\]HÛİY™\İÜ™H™\\˜][Ûˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆ™]\›ˆÛX[\^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ›Üˆİ\œ™[
CBˆCBƒBˆXZ[XİÜƒBˆ[˜È]]Üš^™Q^\š[Y[[ÛİYÙY\ØØ[Üš]JBˆÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
˜\ˆX[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆX[šY™\İœİ]HOHœ™\\™YBˆX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^OHÛÛ^BˆX[šY™\İš\ÒÙY\ØØ[˜[œÜÜ^[ØYBˆÙ[‹˜›İ[™ÙY\ØØ[˜[œÜÜ^[ØY
›ÜˆX[šY™\İ
HOHš[BˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’Q[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆX[šY™\İœİ]HHšÙY\ØØ[Üš]P]]Üš^™YBˆÈÃBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆ™]\›ˆYCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ]]Üš^™HÙY\[ØØ[›İšY\ˆ™\^Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBƒBˆXZ[XİÜƒBˆ[˜È]]Üš^™Q^\š[Y[[ÛİY™\İÜ™PÛÛ[Z]
BˆÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
˜\ˆX[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆX[šY™\İœİ]HOHœ™\\™YX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™YBˆ]™\\™YÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^BˆÙ[‹™^\š[Y[[ÛİY™\İÜ™P›İ[™\P]]Üš]SX]Ú\ÊBˆ™\\™YÛÛ^BˆÛÛ^Bˆ
KBˆÙ[‹š\Õ˜[Y^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^
ÛÛ^
KBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’Q[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™YÃBˆİX\™]›İšY\ˆHÛİYŞ[˜Ô›İšY\Š˜]Õ˜[YNˆÛÛ^œ›İšY\”˜]Õ˜[YJKBˆ\Ù\‘Y˜][Ëœİ[™\™˜›ÛÛ
Bˆ›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[›İ[™\T[™[™ÒÙ^CBˆ
KBˆ\Ù\‘Y˜][Ëœİ[™\™š[YÙ\ŠBˆ›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Ù[™\˜][Û’Ù^CBˆ
HOHÛÛ^™Ù[™\˜][Û‹Bˆ\Ù\‘Y˜][Ëœİ[™\™œİš[™ÊBˆ›Ü’Ù^Nˆ›İšY\‹œ[™[™ĞXØÛİ[Y[]RÙ^CBˆ
HOHÛÛ^œ[™[™ÒY[]H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆCBˆX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^HÛÛ^BˆX[šY™\İœİ]HH˜ÛÛ[Z]]]Üš^™YBˆÈÃBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆ™]\›ˆYCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ]]Üš^™HHXØÛİ[X›İ[™\H™XÛİ™\HÛÛ[Z]ˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBƒBˆXZ[XİÜƒBˆ\ØØ\™X›T™\İ[Bˆ[˜ÈÛÛ\]Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
˜\ˆX[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆX[šY™\İœİ]HOHœ™\\š[™ËBˆX[šY™\İœİ]HOHšÙY\ØØ[Üš]P]]Üš^™Y[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆX[šY™\İœİ]HOH˜ÛÛ[Z]]]Üš^™YÃBˆÚYˆÜÊSÔÊCBˆİX\™]ÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^BˆÛÛ\]P]]Üš^™YXØÛİ[›İ[™\JÛÛ^
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ]]Üš^™YXØÛİ[X›İ[™\H™XÛİ™\H™[XZ[œÈ[™[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[ÙCBˆ™]\›ˆ˜[ÙCBˆÙ[™YƒBˆCBˆİX\™\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆX[šY™\İœİ]HOH˜ÛÛ\]YÃBˆX[šY™\İœİ]HH˜ÛÛ\]YBˆÈÃBˆHÙ[‹Üš]Q^\š[Y[[ÛİY™\İÜ™SX[šY™\İ
X[šY™\İ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İX\šÈÛİY™\İÜ™H™XÛİ™\HÛÛ\]Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBˆ™]\›ˆÛX[\^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ›ÜˆX[šY™\İ
CBˆCBƒBˆXZ[XİÜƒBˆ[˜È™XÛİ™\’[\œ\Y^\š[Y[[ÛİY™\İÜ™RY“™YYY

HÃBˆİX\™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈOHš[[ÙHÈ™]\›ˆCBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™BˆİÚ]ÚÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

HÃBˆØ\ÙH›Z\ÜÚ[™ÎƒBˆYˆY˜][Ë˜›ÛÛ
›Ü’Ù^NˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^JHÃBˆİÚ]ÚÙ[‹›ØYYØXŞQ^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ

HÃBˆØ\ÙH›ØYY
]ØY™PÛİY]JNƒBˆ™XÛİ™\“YØXŞQ^\š[Y[[ÛİY™\İÜ™JØY™PÛİY]JCBˆØ\ÙH[˜]˜Z[X›J]™X\ÛÛŠNƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“YØXŞHÛİY™\İÜ™H™XÛİ™\H\ÈØZ][™È›Üˆ›İXİY]H

™X\ÛÛŠJH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆØ\ÙHš[˜[Y
]™X\ÛÛŠNƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“YØXŞHÛİY™\İÜ™H™XÛİ™\H\È›ØÚÙYH[ˆ[˜[YÛ˜\Úİ

™X\ÛÛŠJH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆØ\ÙH›Z\ÜÚ[™ÎƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİY™\İÜ™H™XÛİ™\H\È›ØÚÙY™XØ]\ÙH›İ]ÈX[šY™\İ[™YØXŞHÛ˜\Úİ\™HZ\ÜÚ[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆ™]\›ƒBˆCBˆYˆÛX[\Üœ[™Y^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ
HÃBˆ™\İ[YTŞ[˜ĞY\‘^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
CBˆCBˆØ\ÙH[˜]˜Z[X›J]™X\ÛÛŠNƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİY™\İÜ™H™XÛİ™\H\ÈØZ][™È›Üˆ›İXİY]H

™X\ÛÛŠJH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆØ\ÙHš[˜[Y
]™X\ÛÛŠNƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİY™\İÜ™H™XÛİ™\H\È›ØÚÙYH[ˆ[˜[YX[šY™\İ

™X\ÛÛŠJH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆØ\ÙH›ØYY
]X[šY™\İ
NƒBˆYˆ]Xİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİY™\İÜ™H™XÛİ™\H™Y\ÙYHZ\ÛX]ÚYXİ]™H˜[œØXİ[Ûˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ƒBˆCBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QHX[šY™\İ˜[œØXİ[Û’QBˆİÚ]ÚX[šY™\İœİ]HÃBˆØ\ÙHœ™\\š[™ÎƒBƒBˆYˆ\ØØ\™™\\š[™Ñ^\š[Y[[ÛİY™\İÜ™JX[šY™\İ
HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘\ØØ\™Y[ˆ[\œ\YÛİY™\İÜ™H™\\˜][Ûˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆØ\ÙH˜ÛÛ\]YƒBˆİX\™\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
H[ÙHÈ™]\›ˆCBˆÈHÛX[\^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ›ÜˆX[šY™\İ
CBˆØ\ÙH˜ÛÛ[Z]]]Üš^™YƒBƒBˆYˆÛÛ\]Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘š[˜[^™Y[ˆ[\œ\YÛÛ[Z]YXØÛİ[X›İ[™\H™\İÜ™H‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆØ\ÙHšÙY\ØØ[Üš]P]]Üš^™YƒBƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ]]Üš^™YÙY\[ØØ[ÛİY™XÛİ™\H\ÈØZ][™È›Üˆ›İšY\ˆ™\^H‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆØ\ÙHœ™\\™YƒBˆ™XÛİ™\”™\\™Y^\š[Y[[ÛİY™\İÜ™JX[šY™\İ
CBˆCBˆCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™XÛİ™\“YØXŞQ^\š[Y[[ÛİY™\İÜ™JÈØY™PÛİY]Nˆ]JHÃBˆİX\™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈOHš[[ÙHÈ™]\›ˆCBˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈH\ÚÈÈXZ[XİÜˆİÙXZÈÙ[—H[ƒBˆİX\™]Ù[ˆ[ÙHÈ™]\›ˆCBˆY™\ˆÈÙ[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈHš[CBˆİX\™]ØZ]Ù[‹œ™\İÜ™Q^\š[Y[[ÛİYÛ˜\Úİ
Bˆœ›ÛNˆØY™PÛİY]KBˆ™\Ù\™SYYXTİ]Q›ÜÛİYÚ]ˆ˜[ÙCBˆ
HOHš[[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“YØXŞHÛİY™\İÜ™H™XÛİ™\H™[XZ[œÈ[™[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ƒBˆCBƒBˆİX\™Ù[‹™\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“YØXŞHÛİY™\İÜ™H™XÛİ™\HÛİ[›İ\˜X›HÛÛ[Z]‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ƒBˆCBˆİX\™Ù[‹˜ÛX[\Üœ[™Y^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“YØXŞHÛİY™\İÜ™HÛÛ\]Y]]Èİ[H\Y˜XİÛİ[›İ™H™[[İ™Y‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ƒBˆCBˆÙ[‹œ™\İ[YTŞ[˜ĞY\‘^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
CBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™XÛİ™\™YØØ[İ]Hœ›ÛHH™[X\ÙYÛİY™\İÜ™H›Ü›X]‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™XÛİ™\”™\\™Y^\š[Y[[ÛİY™\İÜ™JBˆÈX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HÃBˆİX\™Ù[‹˜›İ[™^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ
›ÜˆX[šY™\İ
HOHš[[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™\\™YÛİY™\İÜ™H™XÛİ™\HÛ˜\ÚİİÛ™\œÚ\\ÈZ\ÜÚ[™ÈÜˆ[˜[Y‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ƒBˆCBˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈH\ÚÈÈXZ[XİÜˆİÙXZÈÙ[—H[ƒBˆİX\™]Ù[ˆ[ÙHÈ™]\›ˆCBˆY™\ˆÈÙ[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\U\ÚÈHš[CBˆ]™\İÜ™YH]ØZ]Ù[‹œ™\İÜ™T™\\™Y^\š[Y[[ÛİY™\İÜ™JX[šY™\İ
CBˆYˆ™\İÜ™YÙ[‹˜ÛÛ\]Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”™XÛİ™\™YØØ[İ]HY\ˆ[ˆ[\œ\YÛİY™\İÜ™H‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ’[\œ\YÛİY™\İÜ™H™XÛİ™\H™[XZ[œÈ[™[™È‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™\İÜ™T™\\™Y^\š[Y[[ÛİY™\İÜ™JBˆÈX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
H\Ş[˜ÈOˆ›ÛÛÃBˆİX\™]›İ[™Û˜\ÚİHÙ[‹˜›İ[™^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ
Bˆ›ÜˆX[šY™\İBˆ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆİÚ]ÚX[šY™\İœ™XÛİ™\RÚ[™ÃBˆØ\ÙH˜XØÛİ[›İ[™\NƒBˆİX\™]ÛÛ^HX[šY™\İ˜XØÛİ[›İ[™\PÛÛ^[ÙHÈ™]\›ˆ˜[ÙHCBˆ]›İXİY›Ùš[RQÈHÙ]
ÛÛ^›İ]ÛÚ[™Ô›Ùš[RQÊCBˆ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y˜™YÚ[•[]]™PXØÛİ[›İ[™\PÜ™Y[X[™\Ù\˜][ÛŠBˆ›Ùš[RQÎˆ›İXİY›Ùš[RQÃBˆ
CBˆ]™\İÜ™YØØ[İ]HH]ØZ]™\İÜ™P˜XÚİ\
œ›ÛNˆ›İ[™Û˜\Úİ\›
CBˆİX\™™\İÜ™YØØ[İ]H[ÙHÈ™]\›ˆ˜[ÙHCBˆİX\™X[šY™\İš\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\H[ÙHÃBƒBˆ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y™[™[]]™PXØÛİ[›İ[™\PÜ™Y[X[™\Ù\˜][ÛŠBˆ›Ùš[RQÎˆ›İXİY›Ùš[RQÃBˆ
CBˆ™]\›ˆYCBˆCBˆÚYˆÜÊSÔÊCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆ]™\İÜ™YØ[›ÛšXØ[\˜Ú]™HHYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆœ™\İÜ™T™[[İPXØÛİ[›İ[™\P\˜Ú]™T™XÛİ™\JBˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
CBˆYˆ™\İÜ™YØ[›ÛšXØ[\˜Ú]™HÃBˆ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y™[™[]]™PXØÛİ[›İ[™\PÜ™Y[X[™\Ù\˜][ÛŠBˆ›Ùš[RQÎˆ›İXİY›Ùš[RQÃBˆ
CBˆCBˆ™]\›ˆ™\İÜ™YØ[›ÛšXØ[\˜Ú]™CBˆCBˆÙ[™YƒBˆ™]\›ˆ˜[ÙCBˆØ\ÙH›Ü™[˜\PÛİY™\İÜ™NƒBˆ™]\›ˆ]ØZ]™\İÜ™P˜XÚİ\
œ›ÛNˆ›İ[™Û˜\Úİ\›
CBˆCBˆCBƒBˆXZ[XİÜƒBˆ[˜È›Û˜XÚÔ™\\™Y^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
H\Ş[˜ÈOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
]X[šY™\İ
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’Q[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆYˆX[šY™\İœİ]HOH˜ÛÛ[Z]]]Üš^™YÃBˆ™]\›ˆÛÛ\]Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
CBˆCBˆİX\™X[šY™\İœİ]HOHœ™\\™YBˆÙ[‹˜›İ[™^\š[Y[[ÛİY™\İÜ™TÛ˜\Úİ
›ÜˆX[šY™\İ
HOHš[[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]™\İÜ™YH]ØZ]™\İÜ™T™\\™Y^\š[Y[[ÛİY™\İÜ™JX[šY™\İ
CBˆİX\™™\İÜ™Y[ÙHÈ™]\›ˆ˜[ÙHCBˆ™]\›ˆÛÛ\]Q^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
CBˆCBƒBˆÚYˆÜÊSÔÊCBˆXZ[XİÜƒBˆš]˜]H[˜ÈÛÛ\]P]]Üš^™YXØÛİ[›İ[™\JBˆÈÛÛ^ˆ^\š[Y[[ÛİY™\İÜ™P›İ[™\PÛÛ^Bˆ
HOˆ›ÛÛÃBˆ]\ÜÜÚ][ÛˆHÙ[‹˜]]Üš^™Y™\^Q\ÜÜÚ][ÛŠ›ÜˆÛÛ^
CBˆ]Y[]T\œÚ\İYˆ›ÛÛBˆİÚ]Ú\ÜÜÚ][ÛˆÃBˆØ\ÙH˜YÜ[™[™Ê]›İšY\ŠNƒBˆ]Y˜][ÈH\Ù\‘Y˜][Ëœİ[™\™BˆYˆ][™[™ÒY[]HHÛÛ^œ[™[™ÒY[]HÃBˆY˜][ËœÙ]
[™[™ÒY[]K›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]RÙ^JCBˆY˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]U[œ™\ÛÛ™YÙ^JCBˆH[ÙHÃBˆY˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]RÙ^JCBˆY˜][ËœÙ]
YK›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[Y[]U[œ™\ÛÛ™YÙ^JCBˆCBˆY˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^Nˆ›İšY\‹œ[™[™ĞXØÛİ[Y[]RÙ^JCBˆY˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^Nˆ›İšY\‹˜XØÛİ[›İ[™\T[™[™ÒÙ^JCBˆY[]T\œÚ\İYHY˜][ËœŞ[˜Ú›Ûš^™J
CBˆØ\ÙH˜[™XYPYÜYƒBˆY[]T\œÚ\İYH\Ù\‘Y˜][Ëœİ[™\™œŞ[˜Ú›Ûš^™J
CBˆØ\ÙHœİ\\œÙYYÛÛ›™Xİ[ÛƒBƒBˆY[]T\œÚ\İYHYCBˆØ\ÙH[˜]˜Z[X›Kš[˜[YƒBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™Y[]T\œÚ\İY[ÙHÈ™]\›ˆ˜[ÙHCBƒBˆ]›Ùš[RQÈHÙ]
ÛÛ^›İ]ÛÚ[™Ô›Ùš[RQÊCBˆ]ÛX[\›Ùš[RQÈH^\š[Y[[ÛİY˜XÚÙ\XØÛİ[›İ[™\TÛXŞKœ›Ùš[RQÕĞÛX\ŠBˆİ]ÛÚ[™Ô›Ùš[RQÎˆ›Ùš[RQËBˆ™\İÜ™Y˜XÚÙ\”›Ùš[RQÎˆÙ]
ÛÛ^œ™\İÜ™Y˜XÚÙ\”›Ùš[RQÊCBˆ
CBˆ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y™[™[]]™PXØÛİ[›İ[™\PÜ™Y[X[™\Ù\˜][ÛŠBˆ›Ùš[RQÎˆ›Ùš[RQÃBˆ
CBˆ˜\ˆ˜XÚÙ\ÛX[\\Ñ\˜X›T›İXİYHYCBˆ›Üˆ›Ùš[RQ[ˆÛX[\›Ùš[RQÈÃBˆ˜XÚÙ\ÛX[\\Ñ\˜X›T›İXİYH˜XÚÙ\“X[˜YÙ\‹œÚ\™YBˆ˜ÛX\”İÜ™Q›ÜÛÛ™š\›YYXØÛİ[›İ[™\J›Ùš[RQˆ›Ùš[RQ
CBˆ	‰ˆ˜XÚÙ\ÛX[\\Ñ\˜X›T›İXİYBˆCBˆİX\™˜XÚÙ\ÛX[\\Ñ\˜X›T›İXİY[ÙHÈ™]\›ˆ˜[ÙHCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆ™]\›ˆYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™Y™š[˜[^™SYYXTİ]T™[[İPXØÛİ[›İ[™\J
CBˆCBˆ™]\›ˆYCBˆCBˆÙ[™YƒBƒBˆXZ[XİÜƒBˆš]˜]H[˜È\˜X›PÛX\‘^\š[Y[[ÛİY™\İÜ™T[™[™ÓZ\œ›ÜŠ
HOˆ›ÛÛÃBˆ\Ù\‘Y˜][Ëœİ[™\™œÙ]
˜[ÙK›Ü’Ù^NˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^JCBˆİX\™\Ù\‘Y˜][Ëœİ[™\™œŞ[˜Ú›Ûš^™J
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ\˜X›HÛX\ˆHÛİY™\İÜ™H[™[™ÈZ\œ›Üˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆ™]\›ˆYCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™[X\ÙSYYXTİ]T™XÛİ™\U˜[œØXİ[ÛŠBˆ›ÜˆX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HOˆ›ÛÛÃBˆİX\™X[šY™\İš\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Ûˆ[ÙHÈ™]\›ˆYHCBˆÚYˆÜÊSÔÊCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆYˆX[šY™\İš\ĞØ[›ÛšXØ[\˜Ú]™T™XÛİ™\HÃBˆ™]\›ˆYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆ˜ÛÛ\]T™[[İPXØÛİ[›İ[™\P\˜Ú]™T™XÛİ™\JBˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
CBˆCBˆ™]\›ˆYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆ˜ÛÛ\]SYYXTİ]TŞ[˜Ô™\\™Y™XÛİ™\JBˆ˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’QBˆ
CBˆCBˆÙ[™YƒBˆ™]\›ˆ˜[ÙCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜ÈÛX[\^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊBˆ›ÜˆX[šY™\İˆ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\SX[šY™\İBˆ
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›ØYY
]İ\œ™[
HHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆİ\œ™[˜[œØXİ[Û’QOHX[šY™\İ˜[œØXİ[Û’QBˆİ\œ™[œİ]HOH˜ÛÛ\]YBˆÙ[‹˜›İ[™^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\\Õ˜[Y›ÜÛX[\
X[šY™\İ
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]š[SX[˜YÙ\ˆHš[SX[˜YÙ\‹™Y˜][Bˆ›Üˆ\›[ˆÃBˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\UT“
˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’Q
KBˆÙ[‹™^\š[Y[[ÛİY™\İÜ™SİÛ™\œÚ\T“
˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’Q
KBˆÙ[‹™^\š[Y[[ÛİY™\İÜ™U˜[œÜÜT“
˜[œØXİ[Û’QˆX[šY™\İ˜[œØXİ[Û’Q
CBˆK˜ÛÛ\XİX\
È	JHÚ\™Hš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆ\›œ]
HÃBˆÈÃBˆHš[SX[˜YÙ\‹œ™[[İ™R][J]ˆ\›
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ™[[İ™H›İXİYÛİY™\İÜ™H™XÛİ™\H\Y˜Xİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBˆYˆX[šY™\İš\ÓYYXTİ]T™XÛİ™\U˜[œØXİ[Û‹Bˆ\™[X\ÙSYYXTİ]T™XÛİ™\U˜[œØXİ[ÛŠ›ÜˆX[šY™\İ
HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İÛÛ\]HH›İ[™YYXK\İ]H™XÛİ™\H˜[œØXİ[Ûˆ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]X[šY™\İT“HÙ[‹™^\š[Y[[ÛİY™\İÜ™SX[šY™\İT“[ÙHÈ™]\›ˆ˜[ÙHCBˆÈÃBˆYˆš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆX[šY™\İT“œ]
HÃBˆHš[SX[˜YÙ\‹œ™[[İ™R][J]ˆX[šY™\İT“
CBˆCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ™[[İ™HÛÛ\]YÛİY™\İÜ™HX[šY™\İˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆXİ]™Q^\š[Y[[ÛİY™\İÜ™U˜[œØXİ[Û’QHš[Bˆ™\İ[YTŞ[˜ĞY\‘^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
CBˆ™]\›ˆYCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜ÈÛX[\Üœ[™Y^\š[Y[[ÛİY™\İÜ™P\Y˜XİÊ
HOˆ›ÛÛÃBˆİX\™Ø\ÙH›Z\ÜÚ[™ÈHÙ[‹›ØY^\š[Y[[ÛİY™\İÜ™SX[šY™\İ

KBˆU\Ù\‘Y˜][Ëœİ[™\™˜›ÛÛ
›Ü’Ù^NˆÙ[‹™^\š[Y[[ÛİY™\İÜ™T[™[™ÒÙ^JH[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]š[SX[˜YÙ\ˆHš[SX[˜YÙ\‹™Y˜][Bˆ˜\ˆİXØÙYYYHYCBˆİX\™]\™XİÜHHÙ[‹™^\š[Y[[ÛİY™\İÜ™Q\™XİÜUT“[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]\›ÎˆÕT“CBˆÈÃBˆ\›ÈHHš[SX[˜YÙ\‹˜ÛÛ[ÓÙ‘\™XİÜJBˆ]ˆ\™XİÜKBˆ[˜ÛY[™Ô›Ü\Y\Ñ›Ü’Ù^\Îˆš[Bˆ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ[[Y\˜]HÜœ[™YÛİY™\İÜ™H™XÛİ™\H\Y˜XİÎˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆ›Üˆ\›[ˆ\›ÈÃBˆ]˜[YHH\››\İ]ÛÛ\Û™[Bˆ]\ÓYØXŞHH˜[YHOHÙ[‹›YØXŞQ^\š[Y[[ÛİY™\İÜ™T™XÛİ™\Qš[[˜[YCBˆ]\Ğ›İ[™™XÛİ™\HH˜[YKš\Ô™Yš^
Ù[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\T™Yš^
CBˆ	‰ˆ˜[YKš\ÔİY™š^
Ù[‹™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\TİY™š^
CBˆ	‰ˆ˜[YHOHÛİYŞ[˜Ô™\İÜ™T™XÛİ™\K›X[šY™\İšœÛÛˆƒBˆİX\™\ÓYØXŞH\Ğ›İ[™™XÛİ™\H[ÙHÈÛÛ[YHCBˆÈÃBˆHš[SX[˜YÙ\‹œ™[[İ™R][J]ˆ\›
CBˆHØ]ÚÃBˆİXØÙYYYH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆÛİ[›İ™[[İ™HÜœ[™YÛİY™\İÜ™H™XÛİ™\H\Y˜Xİˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆCBˆÚYˆÜÊSÔÊCBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠKBˆSYYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™Y˜ÛÛ\]T™[[İPXØÛİ[›İ[™\P\˜Ú]™T™XÛİ™\JBˆ˜[œØXİ[Û’Qˆš[Bˆ
HÃBˆİXØÙYYYH˜[ÙCBˆCBˆÙ[™YƒBˆ™]\›ˆİXØÙYYYBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™\İ[YTŞ[˜ĞY\‘^\š[Y[[ÛİY™\İÜ™T™XÛİ™\J
HÃBˆYˆØ]˜Z[X›JSÔÈMËŒ“ÔÈMËŒ
ŠHÃBˆYYXTİ]TŞ[˜Ğ›Ûİİ˜\œ™\İ[YPY\XØÛİ[›İ[™\T™XÛİ™\J
CBˆCBˆ›İYšXØ][ÛÙ[\‹™Y˜][œÜİ
Bˆ˜[YNˆ™^\š[Y[[ÛİY™\İÜ™T™XÛİ™\QYÛÛ\]KBˆØš™Xİˆš[Bˆ
CBˆCBƒBœš]˜]HİXİØÛÜYÙ][™ÜÑY˜][ÈÃBƒBˆ˜\ˆ\Y\Ô›Ùš[TØÛÜYÜš]\ÈHYCBƒBˆ˜\ˆ\Y\ÔÙ\šXÙ\ÔØÛÜYÜš]\ÈHYCBƒBˆ˜\ˆXÛÙYÜ]™[Ù][™ÒÙ^\ÎˆÙ]İš[™ÏÈHš[BƒBˆ˜\ˆ[Ü]™[Ù][™ÜÕÙ\™PØ\\™YHYCBƒBˆš]˜]H[˜ÈİÜ™JÈÙ^Nˆİš[™ÊHOˆ\Ù\‘Y˜][ÈÃBˆ›Ùš[TÙ][™ÜÔİÜ™KœİÜ™J›ÜˆÙ^JCBˆCBƒBˆš]˜]H[˜ÈØ[•Üš]JÈÙ^Nˆİš[™ÊHOˆ›ÛÛÃBˆYˆ]XÛÙYÜ]™[Ù][™ÒÙ^\ËBˆP˜XÚİ\]KÜ]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^NˆÙ^KBˆXÛÙYÚ\™RÙ^\ÎˆXÛÙYÜ]™[Ù][™ÒÙ^\ËBˆ[Ù][™ÜÕÙ\™PØ\\™Yˆ[Ü]™[Ù][™ÜÕÙ\™PØ\\™YBˆ
HÃBˆ™]\›ˆ˜[ÙCBˆCBˆİÚ]ÚXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHÃBˆØ\ÙHœ›Ùš[Nˆ™]\›ˆ\Y\Ô›Ùš[TØÛÜYÜš]\ÃBˆØ\ÙHœÙ\šXÙ\Îˆ™]\›ˆ\Y\ÔÙ\šXÙ\ÔØÛÜYÜš]\ÃBˆØ\ÙH™]šXÙNˆ™]\›ˆYCBˆCBˆCBƒBˆ[˜ÈÙ]
È˜[YNˆ[OË›Ü’Ù^HÙ^Nˆİš[™ÊHÃBˆİX\™Ø[•Üš]JÙ^JH[ÙHÈ™]\›ˆCBˆİÜ™JÙ^JKœÙ]
˜[YK›Ü’Ù^NˆÙ^JCBˆCBˆ[˜È™[[İ™SØš™Xİ
›Ü’Ù^HÙ^Nˆİš[™ÊHÃBˆİX\™Ø[•Üš]JÙ^JH[ÙHÈ™]\›ˆCBˆİÜ™JÙ^JKœ™[[İ™SØš™Xİ
›Ü’Ù^NˆÙ^JCBˆCBˆ[˜ÈØš™Xİ
›Ü’Ù^HÙ^Nˆİš[™ÊHOˆ[OÈÈİÜ™JÙ^JK›Øš™Xİ
›Ü’Ù^NˆÙ^JHCBˆ[˜Èİš[™Ê›Ü’Ù^HÙ^Nˆİš[™ÊHOˆİš[™ÏÈÈİÜ™JÙ^JKœİš[™Ê›Ü’Ù^NˆÙ^JHCBˆ[˜È›ÛÛ
›Ü’Ù^HÙ^Nˆİš[™ÊHOˆ›ÛÛÈİÜ™JÙ^JK˜›ÛÛ
›Ü’Ù^NˆÙ^JHCBˆ[˜È[YÙ\Š›Ü’Ù^HÙ^Nˆİš[™ÊHOˆ[ÈİÜ™JÙ^JKš[YÙ\Š›Ü’Ù^NˆÙ^JHCBˆ[˜ÈİX›J›Ü’Ù^HÙ^Nˆİš[™ÊHOˆİX›HÈİÜ™JÙ^JK™İX›J›Ü’Ù^NˆÙ^JHCBˆ[˜È]J›Ü’Ù^HÙ^Nˆİš[™ÊHOˆ]OÈÈİÜ™JÙ^JK™]J›Ü’Ù^NˆÙ^JHCBˆ[˜Èİš[™Ğ\œ˜^J›Ü’Ù^HÙ^Nˆİš[™ÊHOˆÔİš[™×OÈÈİÜ™JÙ^JKœİš[™Ğ\œ˜^J›Ü’Ù^NˆÙ^JHCBƒBˆ[˜ÈXİ[Û˜\T™\™\Ù[][ÛŠ
HOˆÔİš[™Îˆ[WHÃBˆ›Ùš[TÙ][™ÜÔİÜ™K˜Xİ]™K™Xİ[Û˜\T™\™\Ù[][ÛŠ
CBˆCBŸCBƒBˆš]˜]H[˜ÈØ]\˜XÚİ\]JBˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\Úİˆ›ÛÛH˜[ÙKBˆ[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÎˆ›ÛÛH˜[ÙCBˆ
H›İÜÈOˆ˜XÚİ\]HÃBƒBˆİX\™]Ø\\™PÛÛ^H˜XÚİ\Ø\\™PÛÛ^

H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Y\ÙYÈ^Ü[ˆ[œ™XYX›H›Ùš[H›Üİ\ˆ‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹œ›Ùš[T›Üİ\•[œ™XYX›CBˆCBˆ]Ø\\™YØÛÜHHØ\\™PÛÛ^œØÛÜCBˆ]Xİ]™T›Ùš[RQHØ\\™YØÛÜKœ›Ùš[RQBˆ]\Ù\‘Y˜][ÈHØÛÜYÙ][™ÜÑY˜][Ê
CBƒBˆ˜\ˆXØÙ[ÛÛÜ‘]Nˆ]OÃBˆYˆ]ÛÛÜ‘]HH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ˜XØÙ[ÛÛÜˆŠHÃBˆXØÙ[ÛÛÜ‘]HHÛÛÜ‘]CBˆCBˆ]Ù][™ÜÑÜ˜YY[ÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ™XÛ\ÙU[YQÜ˜YY[ÛÛÜˆŠCBˆ]™XY\XØÙ[ÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆœ™XY\XØÙ[ÛÛÜˆŠCBˆ]™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆœ™XY\•[YQÜ˜YY[ÛÛÜˆŠCBƒBˆ]Ù[XİY\X\˜[˜ÙHH˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆœÙ[XİY\X\˜[˜ÙHŠJCBˆ]™XY\”Ù[XİY\X\˜[˜ÙHH˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\”Ù[XİY\X\˜[˜ÙHŠHÏÈÙ[XİY\X\˜[˜ÙJCBˆ]™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YŠCBˆ][˜X›TİX]\ĞQY˜][H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ™[˜X›TİX]\ĞQY˜][ŠCBˆ]Y˜][İX]S[™İXYÙHH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™Y˜][İX]S[™İXYÙHŠHÏÈ™[™ÈƒBˆ]^Y\”İX]P\X\˜[˜ÙQ[˜X›Yˆ›ÛÛBˆYˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\”İX]P\X\˜[˜ÙQ[˜X›YŠHOHš[ÃBˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ™[˜X›U“ÔİX]QY]Y[HŠH\ÏÈ›ÛÛÏÈYCBˆH[ÙHÃBˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\”İX]P\X\˜[˜ÙQ[˜X›YŠCBˆCBƒBˆ]™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙHH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙHŠHÏÈ™[™ÈƒBˆ]™Y™\œ™Y[š[YP]Y[Ó[™İXYÙHH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙHŠHÏÈšœˆƒBˆ][\^Y\ˆH^X˜XÚÑ[™Ú[™KœÙ[XİY
Bˆ\œÚ\İY[™Ú[™Nˆ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ^X˜XÚÑ[™Ú[™K™Y˜][ÒÙ^JKBˆYØXŞR[\^Y\ˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆš[\^Y\ˆŠH\ÏÈİš[™ËBˆ]šXÙQ˜[Z[Nˆ˜İ\œ™[Bˆ
Kœ˜]Õ˜[YCBˆ]Y“[™İXYÙHH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆY“[™İXYÙHŠHÏÈ™[‹UTÈƒBˆ]ÚİÔØÚY[UXˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÔØÚY[UXˆŠCBˆ]ÚİÓØØ[ØÚY[U[YHH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÓØØ[ØÚY[U[YHŠCBˆ]Y˜][ØÚY[S[ÙHHØÚY[S[ÙKœØ[š]^™Y˜]Õ˜[YJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™Y˜][ØÚY[S[ÙHŠJCBˆ]ØÚY[UÚ[™İÑ^\ÈHØÚY[UÚ[™İËœØ[š]^™Y^\Ê\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆØÚY[UÚ[™İËœİÜ˜YÙRÙ^JH\ÏÈ[
CBˆ]ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”İXœØÜš\[ÛœÊBˆ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈŠCBˆ
CBˆ]ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÊBˆ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈŠCBˆ
CBˆ]ØØ[›İYšXØ][Û‘\\ÛÙSXY[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙSXY[YJBˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û‘\\ÛÙSXY[YHŠH\ÏÈ[Bˆ
CBˆ]ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YJBˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YHŠH\ÏÈ[Bˆ
CBˆ]ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÈH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÈŠH\ÏÈ›ÛÛBƒBˆ]Y˜][^X˜XÚÔÜYYH˜XÚİ\]KœØ[š]^™YY˜][^X˜XÚÔÜYY
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ™Y˜][^X˜XÚÔÜYYŠCBˆ
CBˆ]ÛÜYY^Y\ˆH˜XÚİ\]KœØ[š]^™YÛÜYY^Y\ŠBˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^NˆšÛÜYY^Y\ˆŠCBˆ
CBˆ]^\›˜[^Y\ˆH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™^\›˜[^Y\ˆŠHÏÈ››Û™HƒBˆ]™Y™\‘İÛ›ØYYYYXHH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ™Y™\‘İÛ›ØYYYYXHŠCBˆ][Ø^\Ó[™ØØ\HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜[Ø^\Ó[™ØØ\HŠCBˆ]^Y\”^X˜XÚÓØÚÑ[˜X›YH^Y\”^X˜XÚÓØÚÔÙ][™ÜËš\Ñ[˜X›Y

CBˆ][šTÚÚ\[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ˜[šTÚÚ\[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜[šTÚÚ\[˜X›YŠCBˆ][›Ñ‘[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆš[›Ñ‘[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆš[›Ñ‘[˜X›YŠCBˆ][›Ñ\[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆš[›Ñ\[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆš[›Ñ\[˜X›YŠCBˆ][šTÚÚ\]]ÔÚÚ\H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜[šTÚÚ\]]ÔÚÚ\ŠCBˆ]ÚÚ\\Ñ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚÚ\\Ñ[˜X›YŠCBˆ]ÚÚ\\Ğ[Ø^\Õš\ÚX›HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚÚ\\Ğ[Ø^\Õš\ÚX›HŠCBˆ]ÚİÓ™^\\ÛÙP]ÛˆH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆœÚİÓ™^\\ÛÙP]ÛˆŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÓ™^\\ÛÙP]ÛˆŠCBˆ]ÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆœÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆœÚİÕ“Ñ\\ÛÙPœ›İÜÙ\]ÛˆŠH\ÏÈ›ÛÛÏÈYJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆŠCBˆ]ÚİÔ^Y\”Ù\šXÙ\Ğ]ÛˆH^Y\”Ù\šXÙ\Ğ]Û”Ù][™ÜËš\Ñ[˜X›Y

CBˆ]ÚİÓ™^\\ÛÙTÜİ\]ÛˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÓ™^\\ÛÙTÜİ\]ÛˆŠCBˆ]™^\\ÛÙU™\ÚÛH˜XÚİ\]KœØ[š]^™Y™^\\ÛÙU™\ÚÛ
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ›™^\\ÛÙU™\ÚÛŠCBˆ
CBˆ]™^\\ÛÙTÚÚ\š[\‘[˜X›YH™^\\ÛÙQš[\”Ù][™ÜËš\Ñ[˜X›Y

CBˆ]^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ĞœšYÚ™\ÜÑÙ\İ\™Q[˜X›YŠH\ÏÈ›ÛÛÏÈ˜[ÙJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YŠCBˆ]^Y\•›Û[YQÙ\İ\™Q[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\•›Û[YQÙ\İ\™Q[˜X›YŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›Õ›Û[YQÙ\İ\™Q[˜X›YŠH\ÏÈ›ÛÛÏÈ˜[ÙJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\•›Û[YQÙ\İ\™Q[˜X›YŠCBˆ]^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›Yˆ›ÛÛBˆYˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YŠHOHš[ÃBˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›\•ÛÑš[™Ù\•\[˜X›YŠH\ÏÈ›ÛÛÏÈYCBˆH[ÙHÃBˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YŠCBˆCBˆ]^Y\Ù[\•\^T]\ÙQ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\Ù[\•\^T]\ÙQ[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\Ù[\•\^T]\ÙQ[˜X›YŠCBˆ]^Y\‘İX›U\ÙYZÑ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÑ[˜X›YŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ÑİX›U\ÙYZÑ[˜X›YŠH\ÏÈ›ÛÛÏÈYJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÑ[˜X›YŠCBˆ]Ø]™YİX›U\ÙYZÔÙXÛÛ™ÈH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÔÙXÛÛ™ÈŠHOHš[BˆÈ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ›ÑİX›U\ÙYZÔÙXÛÛ™ÈŠCBˆˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÔÙXÛÛ™ÈŠCBˆ]^Y\‘İX›U\ÙYZÔÙXÛÛ™ÈH˜XÚİ\]KœØ[š]^™Y^Y\‘İX›U\ÙYZÔÙXÛÛ™ÊBˆØ]™YİX›U\ÙYZÔÙXÛÛ™ÃBˆ
CBˆ]^Y\“Ü[”İX]\Ñ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ñ[˜X›YŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ÓÜ[”İX]\Ñ[˜X›YŠH\ÏÈ›ÛÛÏÈ˜[ÙJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ñ[˜X›YŠCBˆ]^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YŠHOHš[BˆÈ
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ÓÜ[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YŠH\ÏÈ›ÛÛÏÈYJCBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YŠCBˆ]^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›YH˜[ÙCBˆ]\‘›Ü™YÜ›İ[™”ÈH\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆ›\‘›Ü™YÜ›İ[™”ÈŠHOHŒÈŒˆÌBˆ]\”™[™\˜XÚÙ[™H˜XÚİ\]KœØ[š]^™YT”™[™\˜XÚÙ[™
\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\”™[™\˜XÚÙ[™ŠJCBˆ]\“Y][]X[]T›Ùš[HH˜XÚİ\]KœØ[š]^™YT“Y][]X[]T›Ùš[J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\“Y][]X[]T›Ùš[HŠJCBˆ]\•\ØØ[[™Ó[ÙHH˜XÚİ\]KœØ[š]^™YT•\ØØ[[™Ó[ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\•\ØØ[[™Ó[ÙHŠJCBˆ]\“™]\˜[\ØØ[\ˆH˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\Š\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\“™]\˜[\ØØ[\ˆŠJCBˆ]\“™]\˜[\ØØ[\•ˆH˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\Š\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\“™]\˜[\ØØ[\•ˆŠJCBˆ]\”^Y\”ÚÚ[ˆH˜XÚİ\]KœØ[š]^™YT”^Y\”ÚÚ[Š\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜËœÚÚ[’Ù^JJCBˆ]\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTš[X\PÛÛÜ’Ù^JCBˆ]\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTÙXÛÛ™\PÛÛÜ’Ù^JCBˆ]\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›YHT”^Y\”ÚÚ[”Ù][™ÜË˜[š[X][ÛœÑ[˜X›Y

CBˆ]\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›HHT”^Y\”ÚÚ[”Ù][™ÜË[ÛÛ›ÛÓÛ›J
CBˆ]\”Xİ\™R[”Xİ\™Q[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›\”Xİ\™R[”Xİ\™Q[˜X›YŠH\ÏÈ›ÛÛÏÈYCBˆ]\\^]Xİ\™R[”Xİ\™Q[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ›\\^]Xİ\™R[”Xİ\™Q[˜X›YŠCBˆ]\’“[ÙHHT’“[ÙJ˜]Õ˜[YNˆ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ›\’“[ÙHŠHÏÈT’“[ÙK™Y˜][[ÙKœ˜]Õ˜[YJOËœ˜]Õ˜[YHÏÈT’“[ÙK™Y˜][[ÙKœ˜]Õ˜[YCBˆ]\”İ\œ›İ[™Ûİ[™[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›\”İ\œ›İ[™Ûİ[™[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ›\”İ\œ›İ[™Ûİ[™[˜X›YŠCBˆ]Ø]ÚÙÙ]\‘[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆØ]ÚÙÙ]\”Ù][™ÜË™[˜X›YÙ^JHOHš[BˆÈØ]ÚÙÙ]\”Ù][™ÜË™Y˜][[˜X›YBˆˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆØ]ÚÙÙ]\”Ù][™ÜË™[˜X›YÙ^JCBˆ]ÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YH˜[ÙCBˆ^\š[Y[[™X]\™Tİ]Kœ™YÚ\İ\‘Y˜][Ê
CBˆ]^\š[Y[[™X]\™\Ñ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K™[˜X›YÙ^JCBˆ]^\š[Y[[™X]\™\Ó\İÚ[™ÙY]H˜XÚİ\]KœØ[š]^™Y^\š[Y[[™X]\™\Ó\İÚ[™ÙY]
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\İÚ[™ÙY]Ù^JCBˆ
CBˆ]^\š[Y[[T”™[ØY[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØY[˜X›YÙ^JCBˆ]^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”Û[Ûİ˜[œÚ][Û‘[˜X›YÙ^JCBˆ]^\š[Y[[T”™[ØYÙ[[\‘[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÙ[[\‘[˜X›YÙ^JCBˆ]^\š[Y[[T”™[ØYÚYšS[Z]PˆH^\š[Y[[™X]\™Tİ]Kœ™\ÛÛ™YT”™[ØYÚYšS[Z]PŠ\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÚYšS[Z]P’Ù^JJCBˆ]^\š[Y[[T”™[ØYÙ[[\“[Z]PˆH^\š[Y[[™X]\™Tİ]Kœ™\ÛÛ™YT”™[ØYÙ[[\“[Z]PŠ\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÙ[[\“[Z]P’Ù^JJCBˆ]^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YHH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”ÚİÔ™[XZ[š[™Õ[YRÙ^JCBˆ]^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™XÚ\ÙT›ÙÜ™\ÜÒÙ^JCBˆ]^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\ÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\’YÛ›Ü™TÜXÚX[İX]Tİ[\ÒÙ^JCBˆ]^\š[Y[[T”™[ØY]]ĞÛX\ˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØY]]ĞÛX\’Ù^JCBˆ]^\š[Y[[PÛİYŞ[˜Ñ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]KšPÛİYŞ[˜Ñ[˜X›YÙ^JCBƒBˆ]İX]Q›Ü™YÜ›İ[™ÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆœİX]\×Ù›Ü™YÜ›İ[™ÛÛÜˆŠCBˆ]İX]Tİ›ÚÙPÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆœİX]\×Üİ›ÚÙPÛÛÜˆŠCBˆ]İX]Tİ›ÚÙUÚYH˜XÚİ\]KœØ[š]^™YİX]Tİ›ÚÙUÚY
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^NˆœİX]\×Üİ›ÚÙUÚYŠCBˆ
CBˆ]İX]Q›ÛÚ^™HH˜XÚİ\]KœØ[š]^™YİX]Q›ÛÚ^™JBˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^NˆœİX]\×Ù›ÛÚ^™HŠCBˆ
CBˆ]İX]U™\XØ[Ù™œÙ]ˆİX›CBˆYˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ^Y\”İX]Sİ™\›^P›İÛPÛÛœİ[ŠHOHš[ÃBˆİX]U™\XØ[Ù™œÙ]H˜XÚİ\]KœØ[š]^™YİX]U™\XØ[Ù™œÙ]
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆœ^Y\”İX]Sİ™\›^P›İÛPÛÛœİ[ŠCBˆ
CBˆH[ÙHYˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›ÔİX]Sİ™\›^P›İÛPÛÛœİ[ŠHOHš[ÃBˆİX]U™\XØ[Ù™œÙ]H˜XÚİ\]KœØ[š]^™YİX]U™\XØ[Ù™œÙ]
Bˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ›ÔİX]Sİ™\›^P›İÛPÛÛœİ[ŠCBˆ
CBˆH[ÙHÃBˆİX]U™\XØ[Ù™œÙ]HM‹ŒBˆCBˆ]İX]\Õš\ÚX›HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœİX]\×Ú\Õš\ÚX›HŠCBƒBˆ]ÚİÒØ[™[ˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÚİÒØ[™[ˆŠCBˆ]YTÜ\ÚØÜ™Y[ˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆšYTÜ\ÚØÜ™Y[ˆŠCBˆ][ÙTİÚ]Ú[š[X][Û‘[˜X›YH[ÙTİÚ]Ú[š[X][Û”Ù][™ÜËš\Ñ[˜X›Y

CBˆ]Ø[™[]]Õ\]S[Ù[\ÈH[Ù[SX[˜YÙ\‹š\Ğ]]Õ\]Q[˜X›YBˆ]ÙX\ÛÛ“Y[HHYYXQ]Z[]›Ü›QY˜][Ë\Ù\ĞÛÛ\XİÙX\ÛÛ“Y[J
CBˆ]Üš^›Û[\\ÛÙS\İHYYXQ]Z[]›Ü›QY˜][Ë\Ù\ÒÜš^›Û[\\ÛÙ\Ê
CBˆ]YYXQ]Z[]P\ÛÜšÑ[˜X›YHYYXQ]Z[]P\ÛÜšÔÙ][™ÜËš\Ñ[˜X›Y

CBˆ]YYXQ]Z[[\›˜]TÜİ\‘[˜X›YHYYXQ]Z[[\›˜]TÜİ\”Ù][™ÜËš\Ñ[˜X›Y

CBˆ]YYXQ]Z[Ú[Z[\•]\Ñ[˜X›YHYYXQ]Z[Ú[Z[\•]\ÔÙ][™ÜËš\Ñ[˜X›Y

CBˆ]\ÙPÛ\ÜÚXÔØÚY[URHH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ\ÙPÛ\ÜÚXÔØÚY[URHŠCBˆ]\›Ğ˜[›™\Ø][ÙÒYH˜XÚİ\]KœØ[š]^™Y›Û‘[\Tİš[™Ê\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆš\›Ğ˜[›™\Ø][ÙÒYŠKY˜][˜[YNˆ™[™[™ÈŠCBˆ]\›Ğ˜[›™\™Z]š[ÜˆH˜XÚİ\]KœØ[š]^™Y\›Ğ˜[›™\™Z]š[ÜŠ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆš\›Ğ˜[›™\™Z]š[ÜˆŠJCBˆ]ÛYPØ][ÙÓ^[İ]İ™\œšY\ÈH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆÛYPØ][ÙÓ^[İ]İÜ™KœİÜ˜YÙRÙ^JK™›]X\Èİš[™Ê]Nˆ	[˜ÛÙ[™Îˆ]
HHÏÈˆƒBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YHÛYP[š[X]Y˜XÚÙÜ›İ[™Ù][™ÜËš\Ñ[˜X›Y

CBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]HH˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]KœİÜ˜YÙRÙ^JJCBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]HH˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]KœİÜ˜YÙRÙ^JJCBˆ]\\™›Ü›X[˜ÙSİ™\›^Q[˜X›YH\\™›Ü›X[˜ÙSİ™\›^TÙ][™ÜËš\Ñ[˜X›Y

CBˆ]^\š[Y[[YYXQ\ÚYÛ”™\Ù]H˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXQ\ÚYÛ”™\Ù]
\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]œİÜ˜YÙRÙ^JJCBˆ]^\š[Y[[\›Ğ›YY]™[H˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YY]™[
\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ^\š[Y[[\›Ğ›YY]™[œİÜ˜YÙRÙ^JJCBˆ]^\š[Y[[ÛYPØ\™Ú\HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÛYPØ\™Ú\J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ^\š[Y[[ÛYPØ\™Ú\KœİÜ˜YÙRÙ^JJCBˆ]^\š[Y[[][QÜ˜YY[[]HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[][QÜ˜YY[[]J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ^\š[Y[[][QÜ˜YY[[]KœİÜ˜YÙRÙ^JJCBˆ]^\š[Y[[\›ÒZYÚØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›ÒZYÚØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›ÒZYÚØØ[RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›ÒZYÚØØ[JJCBˆ]^\š[Y[[\›Ğ›YYİ™[™İH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YYİ™[™İ
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›Ğ›YYİ™[™İÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›Ğ›YYİ™[™İ
JCBˆ]^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›Ñ˜YQ\İ[˜ÙTØØ[RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›Ñ˜YQ\İ[˜ÙTØØ[JJCBˆ]^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™ËœÙXİ[Û”ÜXÚ[™ÔØØ[RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][ÙXİ[Û”ÜXÚ[™ÔØØ[JJCBˆ]^\š[Y[[Ø\™˜Y]\ÔØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ø\™˜Y]\ÔØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë˜Ø\™˜Y]\ÔØØ[RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ø\™˜Y]\ÔØØ[JJCBˆ]^\š[Y[[YYXPØ\™ØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXPØ\™ØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë›YYXPØ\™ØØ[RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][YYXPØ\™ØØ[JJCBˆ]^\š[Y[[Û\ÜÔİ™[™İH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Û\ÜÔİ™[™İ
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Û\ÜÔİ™[™İÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Û\ÜÔİ™[™İ
JCBˆ]^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÈH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÊ˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[˜\ÙQ\šÛ™\ÜÒÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[˜\ÙQ\šÛ™\ÜÊJCBˆ]^\š[Y[[Ü˜YY[XØÙ[[[œÚ]HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[XØÙ[[[œÚ]J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[XØÙ[[[œÚ]RÙ^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[XØÙ[[[œÚ]JJCBˆ]^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛˆH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛŠ˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ØÜ›Û[İ[Û’Ù^JKY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[ØÜ›Û[İ[ÛŠJCBˆ]^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[\ÙPİ\İÛPÛÛÜœÒÙ^JCBˆ]^\š[Y[[Ü˜YY[ÛÛÜHH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜRÙ^JCBˆ]^\š[Y[[Ü˜YY[ÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜ’Ù^JCBˆ]^\š[Y[[Ü˜YY[ÛÛÜÈH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜÒÙ^JCBˆ]][ÜÜ\™Tİ[HH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ˜][ÜÜ\™Tİ[HŠJCBˆ]][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ˜][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHŠJCBˆ]][ÜÜ\™TÛÛYÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆ˜][ÜÜ\™TÛÛYÛÛÜˆŠCBˆ]™XY\][ÜÜ\™Tİ[HH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\][ÜÜ\™Tİ[HŠHÏÈ][ÜÜ\™Tİ[JCBˆ]™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHŠHÏÈ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJCBˆ]™XY\][ÜÜ\™TÛÛYÛÛÜˆH\Ù\‘Y˜][Ë™]J›Ü’Ù^Nˆœ™XY\][ÜÜ\™TÛÛYÛÛÜˆŠCBˆ]YYXQ]Z[[[Y[Ü™\ˆH˜XÚİ\]KœØ[š]^™YYYXQ]Z[[[Y[Ü™\Š\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆYYXQ]Z[[[Y[›Ü™\”İÜ˜YÙRÙ^JJCBˆ]YYXQ]Z[Y[‘[[Y[ÈHYYXQ]Z[[[Y[œ˜]Õ˜[YJ›ÜˆYYXQ]Z[[[Y[šY[‘[[Y[Ê
JCBˆ]™XY\‘]Z[[[Y[Ü™\ˆH˜XÚİ\]KœØ[š]^™Y™XY\‘]Z[[[Y[Ü™\Š\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™XY\‘]Z[[[Y[›Ü™\”İÜ˜YÙRÙ^JJCBˆ]™XY\‘]Z[Y[‘[[Y[ÈH™XY\‘]Z[[[Y[œ˜]Õ˜[YJ›Üˆ™XY\‘]Z[[[Y[šY[‘[[Y[Ê
JCBˆ]YYXPÛÛ[[œÔÜ˜Z]H\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›YYXPÛÛ[[œÔÜ˜Z]ŠHOHš[È\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆ›YYXPÛÛ[[œÔÜ˜Z]ŠHˆÃBˆ]YYXPÛÛ[[œÓ[™ØØ\HH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ›YYXPÛÛ[[œÓ[™ØØ\HŠHOHš[È\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆ›YYXPÛÛ[[œÓ[™ØØ\HŠHˆCBƒBˆ]™XY[™Ó[ÙHH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY[™Ó[ÙHŠHOHš[È\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆœ™XY[™Ó[ÙHŠHˆ™XY[™Ó[ÙK•ÑP•ÓÓ‹œ˜]Õ˜[YCBˆ]Ø[™[”™XY\“[ÙHH˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆšØ[™[”™XY\“[ÙHŠHÏÈ˜XÚİ\]K™Y˜][Ø[™[”™XY\“[ÙT˜]Õ˜[YJ
JCBˆ]\Ù\‘Y˜][ÔÛ˜\ÚİH\Ù\‘Y˜][Ë™Xİ[Û˜\T™\™\Ù[][ÛŠ
CBˆ]Ø[™[”™XY\“[ÙSİ™\œšY\ÈH˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙSİ™\œšY\ÊBˆ\Ù\‘Y˜][ÔÛ˜\Úİœ™YXÙJ[ÎˆÔİš[™Îˆİš[™×J
JHÈ™\İ[][H[ƒBˆİX\™][KšÙ^Kš\Ô™Yš^
šØ[™[”™XY\“[ÙKˆŠKBˆ]˜[YHH][K˜[YH\ÏÈİš[™È[ÙHÈ™]\›ˆCBˆ™\İ[Ôİš[™Ê][KšÙ^K™›Üš\œİ
šØ[™[”™XY\“[ÙKˆ‹˜Ûİ[
JWHH˜[YCBˆCBˆ
CBˆ]™XY\‘İÛœØ[\R[XYÙ\ÈH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹™İÛœØ[\R[XYÙ\ÈŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹™İÛœØ[\R[XYÙ\ÈŠCBˆ]™XY\Ü›Ü›Ü™\œÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹˜Ü›Ü›Ü™\œÈŠCBˆ]™XY\‘\ØX›T]ZXÚĞXİ[ÛœÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹™\ØX›T]ZXÚĞXİ[ÛœÈŠCBˆ]™XY\‘\ØX›QİX›U\H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹™\ØX›QİX›U\ŠCBˆ]™XY\“]™U^H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹›]™U^ŠCBˆ]™XY\’YP˜\œÓÛ”İÚ\HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹šYP˜\œÓÛ”İÚ\HŠCBˆ]™XY\˜XÚÙÜ›İ[™ÛÛÜˆH˜XÚİ\]KœØ[š]^™Y™XY\˜XÚÙÜ›İ[™ÛÛÜŠ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹˜˜XÚÙÜ›İ[™ÛÛÜˆŠJCBˆ]™XY\“ÜšY[][ÛˆH˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][ÛŠ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹›ÜšY[][ÛˆŠJCBˆ]™XY\•\›Û™\ÈH˜XÚİ\]KœØ[š]^™Y™XY\•\›Û™\Ê\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹\›Û™\ÈŠJCBˆ]™XY\’[™\\›Û™\ÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹š[™\\›Û™\ÈŠCBˆ]™XY\[š[X]TYÙU˜[œÚ][ÛœÈH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹˜[š[X]TYÙU˜[œÚ][ÛœÈŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹˜[š[X]TYÙU˜[œÚ][ÛœÈŠCBˆ]™XY\•\ØØ[R[XYÙ\ÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹\ØØ[R[XYÙ\ÈŠCBˆ]™XY\•\ØØ[SX^ZYÚH˜XÚİ\]KœØ[š]^™Y™XY\•\ØØ[SX^ZYÚ
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹\ØØ[SX^ZYÚŠKY˜][˜[YNˆŒ
JCBˆ]™XY\•\ØØ[S[Ù[˜[YHH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹\ØØ[S[Ù[˜[YHŠHÏÈ“›Û™HƒBˆ]™XY\”YÙ\ÕÔ™[ØYH˜XÚİ\]KœØ[š]^™Y™XY\”YÙ\ÕÔ™[ØY
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹œYÙ\ÕÔ™[ØYŠKY˜][˜[YNˆÊJCBˆ]™XY\”YÙYYÙS^[İ]H˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙS^[İ]
\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹œYÙYYÙS^[İ]ŠJCBˆ]™XY\”YÙYYÙSÙ™œÙ]H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹œYÙYYÙSÙ™œÙ]ŠCBˆ]™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ÈH˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ÊBˆ\Ù\‘Y˜][ÔÛ˜\Úİœ™YXÙJ[ÎˆÔİš[™Îˆ›ÛÛJ
JHÈ™\İ[][H[ƒBˆİX\™][KšÙ^Kš\Ô™Yš^
”™XY\‹œYÙYYÙSÙ™œÙ]ˆŠKBˆ]˜[YHH][K˜[YH\ÏÈ›ÛÛ[ÙHÈ™]\›ˆCBˆ™\İ[Ôİš[™Ê][KšÙ^K™›Üš\œİ
”™XY\‹œYÙYYÙSÙ™œÙ]ˆ‹˜Ûİ[
JWHH˜[YCBˆCBˆ
CBˆ]™XY\”Ü]ÚYR[XYÙ\ÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹œÜ]ÚYR[XYÙ\ÈŠCBˆ]™XY\”™]™\œÙTÜ]Ü™\ˆH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹œ™]™\œÙTÜ]Ü™\ˆŠCBˆ]™XY\•™\XØ[[™š[š]TØÜ›ÛH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹™\XØ[[™š[š]TØÜ›ÛŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹™\XØ[[™š[š]TØÜ›ÛŠCBˆ]™XY\”[\˜›ŞH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ”™XY\‹œ[\˜›ŞŠCBˆ]™XY\”[\˜›Ş[[İ[H˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›Ş[[İ[
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ”™XY\‹œ[\˜›Ş[[İ[ŠKY˜][˜[YNˆMJJCBˆ]™XY\”[\˜›ŞÜšY[][ÛˆH˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›ŞÜšY[][ÛŠ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ”™XY\‹œ[\˜›ŞÜšY[][ÛˆŠJCBˆ]™XY\“ÜšY[][Û“ØÚÑ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ™XY\“ÜšY[][Û“ØÚÑ[˜X›YŠCBˆ]™XY\“ÜšY[][Û“ØÚÓX\ÚÈH˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][Û“ØÚÓX\ÚÊ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\“ÜšY[][Û“ØÚÓX\ÚÈŠJCBˆ]™XY\”™XY™\ÚÛ\˜Ù[H˜XÚİ\]KœØ[š]^™Y™XY\”™XY™\ÚÛ\˜Ù[
\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY\”™XY™\ÚÛ\˜Ù[ŠH\ÏÈİX›JCBƒBˆ]™XY\‘›ÛÚ^™HH˜XÚİ\]KœØ[š]^™Y™XY\‘›ÛÚ^™JBˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆœ™XY\‘›ÛÚ^™HŠCBˆ
CBˆ]™XY\‘›Û˜[Z[HH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\‘›Û˜[Z[HŠHÏÈ‹X\K\Ş\İ[HƒBˆ]™XY\‘›ÛÙZYÚH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\‘›ÛÙZYÚŠHÏÈ››Ü›X[ƒBˆ]™XY\ÛÛÜ”™\Ù]H˜XÚİ\]KœØ[š]^™Y™XY\ÛÛÜ”™\Ù]
\Ù\‘Y˜][Ëš[YÙ\Š›Ü’Ù^Nˆœ™XY\ÛÛÜ”™\Ù]ŠJCBˆ]™XY\•^[YÛ›Y[H\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆœ™XY\•^[YÛ›Y[ŠHÏÈ›YƒBˆ]™XY\“[™TÜXÚ[™ÈH˜XÚİ\]KœØ[š]^™Y™XY\“[™TÜXÚ[™ÊBˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆœ™XY\“[™TÜXÚ[™ÈŠCBˆ
CBˆ]™XY\“X\™Ú[ˆH˜XÚİ\]KœØ[š]^™Y™XY\“X\™Ú[ŠBˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY\“X\™Ú[ˆŠHOHš[BˆÈ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆœ™XY\“X\™Ú[ˆŠCBˆˆš[Bˆ
CBƒBˆ]]]ĞÛX\ØXÚQ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜]]ĞÛX\ØXÚQ[˜X›YŠCBˆ]]]ĞÛX\ØXÚU™\ÚÛPˆH˜XÚİ\]KœØ[š]^™Y]]ĞÛX\ØXÚU™\ÚÛPŠBˆ\Ù\‘Y˜][Ë™İX›J›Ü’Ù^Nˆ˜]]ĞÛX\ØXÚU™\ÚÛPˆŠCBˆ
CBˆ]YÚ]X[]U™\ÚÛH˜XÚİ\]KœØ[š]^™YYÚ]X[]U™\ÚÛ
Bˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^NˆšYÚ]X[]U™\ÚÛŠH\ÏÈİX›CBˆ
CBˆ]˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YŠCBˆ]™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YŠCBˆ]™XY\‘İÛ›ØYÕÚYšSÛ›HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆœ™XY\‘İÛ›ØYÕÚYšSÛ›HŠCBˆ]™XY\‘İÛ›ØYÔ\˜[[[Z]H˜XÚİ\]KœØ[š]^™Y™XY\‘İÛ›ØYÔ\˜[[[Z]
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆ\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆœ™XY\‘İÛ›ØYÔ\˜[[[Z]ŠKY˜][˜[YNˆŠJCBˆ]]]Õ\]TÙ\šXÙ\Ñ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ˜]]Õ\]TÙ\šXÙ\Ñ[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ˜]]Õ\]TÙ\šXÙ\Ñ[˜X›YŠCBˆ]Ù\šXÙ\Ğ]]Ó[ÙQ[˜X›YH]]Ó[ÙTÙ][™ÜËš\Ñ[˜X›Y

CBˆ]Ù\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^NˆœÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YŠCBˆ]Ù\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YH]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙTÙ][™ÜËš\Ñ[˜X›Y

CBˆ]Ù\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
\Ù\‘Y˜][Ëœİš[™Ğ\œ˜^J›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈŠJCBˆ]Ù\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
\Ù\‘Y˜][Ëœİš[™Ğ\œ˜^J›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈŠJCBˆ]Ù\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙHH]]Ó[ÙT]X[]T™Y™\™[˜ÙKœØ[š]^™Y˜]Õ˜[YJ\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ]]Ó[ÙT]X[]T™Y™\™[˜ÙKœİÜ˜YÙRÙ^JJCBˆ]Ù\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]HHÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË›Z[š[][TÚ[Z[\š]J
CBˆ]Ù\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ÈHÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË™›ÜÓZ\ÛX]ÚY™\İ[Ê
CBˆ]Ù\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YHÙ\šXÙ\ÔÚY]™\Ù[][Û”Ù][™ÜË\Ù\Ôİ™[Z[Ôİ[J
CBˆ]Ù\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÈHİ™X[S[™İXYÙQš[\‹š[˜ÛYY[™İXYÙ\Ê
CBˆ]Ù\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÈHİ™X[S[™İXYÙQš[\‹šY[“[™İXYÙ\Ê
CBˆ]Ù\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]HHİ™X[S[™İXYÙQš[\‹šY\Ôİ™X[\ÕÚ]İ][™İXYÙQ]J
CBˆ]Ù\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÈHİ™X[S[™İXYÙQš[\‹˜\Üİ[Y\ÓÜšYÚ[˜[]Y[Ê
CBˆ]Ù\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚHİ™X[S[™İXYÙQš[\‹™X]ÑX˜™Y[š[YP\Ñ[™Û\Ú

CBˆ]Ù\šXÙ\ÒY[”İ™X[T]X[]Y\ÈHİ™X[S[™İXYÙQš[\‹šY[”]X[]RZYÚÊ
CBˆ]Ù\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]HHİ™X[S[™İXYÙQš[\‹šY\Ôİ™X[\ÕÚ]İ]]XİY]X[]J
CBˆ]Ù\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈHİ™X[S[™İXYÙQš[\‹™^˜T[\ÔÛİ\˜ÙRYÊ
CBˆ]Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YH\Ù\‘Y˜][Ë›Øš™Xİ
›Ü’Ù^Nˆ™Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YŠHOHš[ÈYHˆ\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ™Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YŠCBˆ]Ú]X”™[X\ÙU\]P]˜Z[X›HH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ™Ú]X”™[X\ÙU\]P]˜Z[X›HŠCBˆ]Ú]X”™[X\ÙS]\İ™\œÚ[ÛˆH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™Ú]X”™[X\ÙS]\İ™\œÚ[ÛˆŠHÏÈˆƒBˆ]Ú]X”™[X\ÙUT“H\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™Ú]X”™[X\ÙUT“ŠHÏÈˆƒBˆ]Ú]X”™[X\ÙTÚİĞ[\[™[™ÈH\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ™Ú]X”™[X\ÙTÚİĞ[\[™[™ÈŠCBˆ]Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^Nˆ™Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆŠHÏÈˆƒBˆ]š[\’Üœ›ÜÛÛ[H\Ù\‘Y˜][Ë˜›ÛÛ
›Ü’Ù^Nˆ™š[\’Üœ›ÜˆŠCBˆ]Ù[XİYÚ[Z[\š]P[ÛÜš]HH˜XÚİ\]KœØ[š]^™YÚ[Z[\š]P[ÛÜš]J\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆœÙ[XİYÚ[Z[\š]P[ÛÜš]HŠJCBˆ]\™›Ü›X[˜ÙS[ÙQ[˜X›YH\™›Ü›X[˜ÙS[ÙTÙ][™ÜËš\Ñ[˜X›YBˆ]\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ÈH\™›Ü›X[˜ÙS[ÙTÙ][™ÜËœÚÚ\Ğ[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ÃBˆ]\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\ÈH\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™˜\İ[š[YPØ][ÙÓİ™\œšY\ÃBˆ]Ø[™[’ÛYTÙ[XİYÛİ\˜ÙRQH\Ù\‘Y˜][Ëœİš[™Ê›Ü’Ù^NˆšØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQŠHÏÈˆƒBˆ]Ø[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
\Ù\‘Y˜][Ëœİš[™Ğ\œ˜^J›Ü’Ù^NˆšØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÈŠJCBƒBˆ]ÙX\˜Ú\İÜNˆ˜XÚİ\ÙX\˜Ú\İÜCBˆYˆ]\İÜQ]HH\Ù\‘Y˜][Ë™]J›Ü’Ù^NˆœÙX\˜Ú\İÜHŠHÃBˆYˆ]XÛÙYH˜XÚİ\ÙX\˜Ú\İÜK™XÛÙY]Y\šY\Êœ›ÛNˆ\İÜQ]JHÃBˆÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJ]Y\šY\ÎˆXÛÙYØ\ĞØ\\™YˆYJCBˆH[ÙHÃBˆÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJ
CBˆCBˆH[ÙHÃBˆÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJØ\ĞØ\\™YˆYJCBˆCBƒBˆ]Xœ˜\SX[˜YÙ\ˆHXœ˜\SX[˜YÙ\‹œÚ\™YBˆ]Xİ]™PÛÛXİ[ÛœÈHXœ˜\SX[˜YÙ\‹˜ÛÛXİ[ÛœÊ›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBƒBˆ]›ÙÜ™\ÜÓX[˜YÙ\ˆH›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™YBˆ]Xİ]™T›ÙÜ™\ÜÈH›ÙÜ™\ÜÓX[˜YÙ\‹œ›ÙÜ™\ÜÑ]J›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]Xİ]™T˜][™ÜÈH\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ˜][™ÜĞ[™›İ\Ê›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBƒBˆ]Xİ]™PØ][ÙÜÈHØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜÑ›Ü˜XÚİ\
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]Xİ]™SX[™ØPÛÛXİ[ÛœÈHX[™ØSXœ˜\SX[˜YÙ\‹œÚ\™YBˆ˜ÛÛXİ[ÛœÔÛ˜\Úİ
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]Xİ]™SX[™ØT›ÙÜ™\ÜÈHX[™ØT™XY[™Ô›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™YBˆœ›ÙÜ™\ÜÔÛ˜\Úİ
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]Xİ]™SX[™ØPØ][ÙÜÈHX[™ØPØ][ÙÓX[˜YÙ\‹œÚ\™YBˆ˜Ø][ÙÜÔÛ˜\Úİ
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]Xİ]™Pİ\İÛPØ][ÙÜÈHØ[™[İ\İÛPØ][ÙÓX[˜YÙ\‹œÚ\™YBˆ˜Ø][ÙÜÔÛ˜\Úİ
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆ]˜XÚÙ\“X[˜YÙ\ˆH˜XÚÙ\“X[˜YÙ\‹œÚ\™YBˆ]Xİ]™U˜XÚÙ\”İ]Nˆ˜XÚÙ\”İ]OÈHÃBˆYˆ™XYš\ÓXZ[•™XYÃBˆ™]\›ˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆÈ˜XÚÙ\“X[˜YÙ\‹˜XÚÙ\”İ]Q›Ü”š]˜]PÛİY^Ü
Bˆ›Ü”›Ùš[NˆXİ]™T›Ùš[RQBˆ
CBˆˆ˜XÚÙ\“X[˜YÙ\‹˜XÚÙ\”İ]J›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆCBˆ™]\›ˆ\Ü]Ú]Y]YK›XZ[‹œŞ[˜ÈÃBˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆÈ˜XÚÙ\“X[˜YÙ\‹˜XÚÙ\”İ]Q›Ü”š]˜]PÛİY^Ü
Bˆ›Ü”›Ùš[NˆXİ]™T›Ùš[RQBˆ
CBˆˆ˜XÚÙ\“X[˜YÙ\‹˜XÚÙ\”İ]J›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBˆCBˆJ
CBˆ˜\ˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œÎˆÔİš[™×HH×CBˆYˆXİ]™PÛÛXİ[ÛœÈOHš[È[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
›Xœ˜\HŠHCBˆYˆXİ]™T›ÙÜ™\ÜÈOHš[È[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
œ›ÙÜ™\ÜÈŠHCBˆYˆXİ]™T˜][™ÜÈOHš[È[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
œ˜][™ÜÈŠHCBˆYˆXİ]™PØ][ÙÜÈOHš[È[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
˜Ø][ÙÜÈŠHCBˆYˆXİ]™U˜XÚÙ\”İ]HOHš[È[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
˜XÚÙ\œÈŠHCBˆYˆXİ]™SX[™ØPÛÛXİ[ÛœÈOHš[ÃBˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
”™XY\ˆXœ˜\HŠCBˆCBˆYˆXİ]™SX[™ØT›ÙÜ™\ÜÈOHš[ÃBˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
”™XY\ˆ›ÙÜ™\ÜÈŠCBˆCBˆYˆXİ]™SX[™ØPØ][ÙÜÈOHš[ÃBˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
”™XY\ˆØ][ÙÜÈŠCBˆCBˆYˆXİ]™Pİ\İÛPØ][ÙÜÈOHš[ÃBˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œË˜\[™
”™XY\ˆİ\İÛHØ][ÙÜÈŠCBˆCBˆİX\™[œ™XYX›PÛÛ\]Xš[]QÛXZ[œËš\Ñ[\KBˆ]Xİ]™PÛÛXİ[ÛœËBˆ]Xİ]™T›ÙÜ™\ÜËBˆ]Xİ]™T˜][™ÜËBˆ]Xİ]™PØ][ÙÜËBˆ]Xİ]™SX[™ØPÛÛXİ[ÛœËBˆ]Xİ]™SX[™ØT›ÙÜ™\ÜËBˆ]Xİ]™SX[™ØPØ][ÙÜËBˆ]Xİ]™Pİ\İÛPØ][ÙÜËBˆ]Xİ]™U˜XÚÙ\”İ]H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Y\ÙYÈ^Ü[œ™XYX›HXİ]™K\›Ùš[HYØXŞHÛXZ[œÈ

[œ™XYX›PÛÛ\]Xš[]QÛXZ[œËš›Ú[™Y
Ù\\˜]Üˆ‹ŠJJH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹˜Xİ]™T›Ùš[PÛÛ\]Xš[]QÛXZ[œÕ[œ™XYX›JBˆ[œ™XYX›PÛÛ\]Xš[]QÛXZ[œÃBˆ
CBˆCBˆ]˜XÚİ\ÛÛXİ[ÛœÈHXİ]™PÛÛXİ[ÛœË›X\È˜XÚİ\ÛÛXİ[ÛŠœ›ÛNˆ	
HCBˆ]›ÙÜ™\ÜÑ]HHXİ]™T›ÙÜ™\ÜÃBƒBˆ]˜XÚÙ\”İ]HH\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆÈXİ]™U˜XÚÙ\”İ]CBˆˆÙ[‹˜XÚÙ\”İ]UÚ]İ]Ü™Y[X[ÊXİ]™U˜XÚÙ\”İ]JCBƒBˆ]Ø][ÙÜÈHXİ]™PØ][ÙÜÃBƒBˆ]Ûİ\˜ÙPØ\\™Nˆ
Ù\šXÙ\ÎˆĞ˜XÚİ\Ù\šXÙWKYÛœÎˆĞ˜XÚİ\İ™[Z[ĞYÛ—JOÈHÃBˆÈÃBˆ]Ù\šXÙ\ÈHHÙ\šXÙTİÜ™KœÚ\™Y˜˜XÚİ\›İÜÊ
K›X\È›İÈ[ƒBˆ˜XÚİ\Ù\šXÙJBˆYˆ›İËšYBˆ\›ˆ›İË\›BˆœÛÛ“Y]Y]Nˆ›İËšœÛÛ“Y]Y]KBˆœÔØÜš\ˆ›İËšœÔØÜš\Bˆ\ĞXİ]™Nˆ›İËš\ĞXİ]™KBˆÛÜ[™^ˆ›İËœÛÜ[™^Bˆ
CBˆCBˆ]YÛœÈHHİ™[Z[ĞYÛ”İÜ™KœÚ\™Y˜˜XÚİ\›İÜÊ
K›X\È›İÈ[ƒBˆ]™\ÛÛ™YT“Hİ™[Z[ĞÛÛ™šYİ\™YT“˜][œ™\ÛÛ™JBˆYÛ’Qˆ›İËšYBˆ\œÚ\İYT“ˆ›İË˜ÛÛ™šYİ\™YT“Bˆ›Ùš[RQˆXİ]™T›Ùš[RQBˆ
CBˆİX\™Tİ™[Z[ĞÛÛ™šYİ\™YT“˜][š\Õ[œ™\ÛÛ™Y™Y™\™[˜ÙJ™\ÛÛ™YT“
H[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ˜ÛÙ\’[˜[Y˜[YJCBˆCBˆ™]\›ˆ˜XÚİ\İ™[Z[ĞYÛŠBˆYˆ›İËšYBˆÛÛ™šYİ\™YT“ˆ™\ÛÛ™YT“BˆX[šY™\İ”ÓÓˆ›İË›X[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™Nˆ›İËš\ĞXİ]™KBˆÛÜ[™^ˆ›İËœÛÜ[™^Bˆ
CBˆCBˆ™]\›ˆ
Ù\šXÙ\ËYÛœÊCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆXİ]™HÙ\šXÙKÔİ™[Z[ÈÛİ\˜ÙHØ\\™HØ\È[˜]˜Z[X›NÈHÛİ\˜ÙH›Üİ\ˆØ\ÈÛZ]Y‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆš[BˆCBˆJ
CBˆ]Ù\šXÙ\ÈHÛİ\˜ÙPØ\\™OËœÙ\šXÙ\ÈÏÈ×CBˆ]İ™[Z[ĞYÛœÈHÛİ\˜ÙPØ\\™OË˜YÛœÃBƒBˆ˜\ˆ]š[ÔYÚ[œÎˆ]š[ÔİÜ™YYÚ[œÔİ]OÈHš[Bˆ\™›Ü›SÛ“XZ[•™XYÃBˆXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆ]]š[ÓX[˜YÙ\ˆH]š[ÔYÚ[“X[˜YÙ\‹œÚ\™YBˆİX\™]š[ÓX[˜YÙ\‹š\ÓØYY[ÙHÈ™]\›ˆCBˆ]š[ÔYÚ[œÈH]š[ÓX[˜YÙ\‹˜˜XÚİ\İ]J
CBˆCBˆCBƒBˆ˜\ˆÚŞTİ™X[NˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİÈHš[Bˆ˜\ˆÚŞTİ™X[P˜XÚİ\\œ›Üˆ\œ›ÜÃBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆ˜\ˆÚŞTİ™X[SX[X[Ø\\™T[ˆÚŞTİ™X[SX[X[˜XÚİ\Ø\\™T[ÃBˆYˆ]Ü\]YTÛ˜\ÚİHØYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
Bˆ™Y™\œš[™ÔØY™PÛİYˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ
HÃBƒBˆÚŞTİ™X[HH\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆÈ˜XÚİ\]KœÚŞTİ™X[TÛ˜\Úİ›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆÜ\]YTÛ˜\ÚİBˆİš\\˜Ú]™\ÎˆZ[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÃBˆ
CBˆˆÜ\]YTÛ˜\ÚİBˆH[ÙHÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆ]X[˜YÙ\ˆHÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™YBˆİX\™X[˜YÙ\‹š\ÓØYY[ÙHÈ™]\›ˆCBˆYˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİÃBˆÚŞTİ™X[HH[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÃBˆÈX[˜YÙ\‹˜ÛÛ\]Tš]˜]PÛİY˜XÚİ\Û˜\Úİ

CBˆˆX[˜YÙ\‹˜ÛÛ\]Tš]˜]PÛİYY]Y]TÛ˜\Úİ

CBˆH[ÙHÃBˆÈÃBƒBˆÚŞTİ™X[SX[X[Ø\\™T[ˆHHX[˜YÙ\‹›X[X[˜XÚİ\Ø\\™T[Š
CBˆHØ]ÚÃBˆÚŞTİ™X[P˜XÚİ\\œ›ÜˆH\œ›ÜƒBˆCBˆCBˆCBˆCBˆCBˆYˆ]ÚŞTİ™X[SX[X[Ø\\™T[‹ÚŞTİ™X[P˜XÚİ\\œ›ÜˆOHš[ÃBˆÈÃBˆÚŞTİ™X[HHHÚŞTİ™X[TYÚ[“X[˜YÙ\‹›X]\šX[^™SX[X[˜XÚİ\Û˜\Úİ
BˆÚŞTİ™X[SX[X[Ø\\™T[ƒBˆ
CBˆHØ]ÚÃBˆÚŞTİ™X[P˜XÚİ\\œ›ÜˆH\œ›ÜƒBˆCBˆCBˆÙ[ÙCBˆYˆ]Ü\]YTÛ˜\ÚİHØYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
Bˆ™Y™\œš[™ÔØY™PÛİYˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ
HÃBˆÚŞTİ™X[HH\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆÈ˜XÚİ\]KœÚŞTİ™X[TÛ˜\Úİ›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆÜ\]YTÛ˜\ÚİBˆİš\\˜Ú]™\ÎˆZ[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÃBˆ
CBˆˆÜ\]YTÛ˜\ÚİBˆCBˆÙ[™YƒBˆYˆ]ÚŞTİ™X[P˜XÚİ\\œ›ÜˆÈ›İÈÚŞTİ™X[P˜XÚİ\\œ›ÜˆCBƒBˆ]X[™ØPÛÛXİ[ÛœÈHXİ]™SX[™ØPÛÛXİ[ÛœË›X\ÈÛÛXİ[Ûˆ[ƒBˆ˜XÚİ\X[™ØPÛÛXİ[ÛŠBˆYˆÛÛXİ[Û‹šYBˆ˜[YNˆÛÛXİ[Û‹›˜[YKBˆ][\ÎˆÛÛXİ[Û‹š][\ËBˆ\ØÜš\[ÛˆÛÛXİ[Û‹™\ØÜš\[ÛƒBˆ
CBˆCBƒBˆ]X[™ØT™XY[™Ô›ÙÜ™\ÜÈHXİ[Û˜\JBˆ[š\]YRÙ^\ÕÚ]˜[Y\ÎˆXİ]™SX[™ØT›ÙÜ™\ÜÃBˆ›X\È
—
	šÙ^JH‹	˜[YJHCBˆ
CBƒBˆ]X[™ØPØ][ÙÜÈHXİ]™SX[™ØPØ][ÙÜÃBƒBˆ]İ\İÛPØ][ÙÜÈHXİ]™Pİ\İÛPØ][ÙÜÃBƒBˆ]Ø[™[“[Ù[\ÈH[Ù[SX[˜YÙ\‹œÚ\™Y›[Ù[\Ë›X\È[Ù[ƒBˆ˜XÚİ\Ø[™[“[Ù[JBˆYˆ[ÙšYBˆ[Ù[Q]Nˆ[Ù›[Ù[Q]KBˆØØ[]ˆ[Ù›ØØ[]Bˆ[Ù[]\›ˆ[Ù›[Ù[]\›Bˆ\ĞXİ]™Nˆ[Ùš\ĞXİ]™CBˆ
CBˆCBƒBˆÚYˆ[ÜÊ“ÔÊCBˆ]™XY\‘^[œÚ[ÛœÔİ]Nˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]OÃBˆÈÃBˆ™XY\‘^[œÚ[ÛœÔİ]HHH˜XÚİ\™XY\‘^[œÚ[Û”İ]K˜Ø\\™JBˆœ›ÛNˆ›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ËBˆ™Y™\™[˜ÙTİÜ™Nˆ›Ùš[TÙ][™ÜÔİÜ™K˜Xİ]™CBˆ
CBˆHØ]ÚÃBˆYˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİÃBˆ™XY\‘^[œÚ[ÛœÔİ]HHš[BˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\ˆXİ]™H™XY\ˆ^[œÚ[ÛˆY]Y]H\È[œ™XYX›NÈÛZ]Yœ›ÛHÛİYÛ˜\Úİ˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆH[ÙHÃBˆ›İÈ\œ›ÜƒBˆCBˆCBˆÙ[ÙCBˆ]™XY\‘^[œÚ[ÛœÔİ]Nˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]OÈHš[BˆÙ[™YƒBƒBˆ]˜XÚİ\H˜XÚİ\]JBˆÜ™X]Y]Nˆ]J
KBˆXØÙ[ÛÛÜˆXØÙ[ÛÛÜ‘]KBˆÙ][™ÜÑÜ˜YY[ÛÛÜˆÙ][™ÜÑÜ˜YY[ÛÛÜ‹Bˆ™XY\XØÙ[ÛÛÜˆ™XY\XØÙ[ÛÛÜ‹BˆY“[™İXYÙNˆY“[™İXYÙKBˆÙ[XİY\X\˜[˜ÙNˆÙ[XİY\X\˜[˜ÙKBˆ™XY\”Ù[XİY\X\˜[˜ÙNˆ™XY\”Ù[XİY\X\˜[˜ÙKBˆ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›Yˆ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YBˆ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜ‹Bˆ[˜X›TİX]\ĞQY˜][ˆ[˜X›TİX]\ĞQY˜][BˆY˜][İX]S[™İXYÙNˆY˜][İX]S[™İXYÙKBˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›Yˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›YBƒBˆ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙNˆ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙKBˆ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙNˆ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙKBˆ[\^Y\ˆ[\^Y\‹BˆÚİÔØÚY[UXˆÚİÔØÚY[UX‹BˆÚİÓØØ[ØÚY[U[YNˆÚİÓØØ[ØÚY[U[YKBˆY˜][ØÚY[S[ÙNˆY˜][ØÚY[S[ÙKBˆØÚY[UÚ[™İÑ^\ÎˆØÚY[UÚ[™İÑ^\ËBˆØØ[›İYšXØ][Û”İXœØÜš\[ÛœÎˆØØ[›İYšXØ][Û”İXœØÜš\[ÛœËBˆØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÎˆØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œËBˆØØ[›İYšXØ][Û‘\\ÛÙSXY[YNˆØØ[›İYšXØ][Û‘\\ÛÙSXY[YKBˆØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YNˆØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YKBˆØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÎˆØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ËBƒBˆY˜][^X˜XÚÔÜYYˆY˜][^X˜XÚÔÜYYBˆÛÜYY^Y\ˆÛÜYY^Y\‹Bˆ^\›˜[^Y\ˆ^\›˜[^Y\‹Bˆ™Y™\‘İÛ›ØYYYYXNˆ™Y™\‘İÛ›ØYYYYXKBˆ[Ø^\Ó[™ØØ\Nˆ[Ø^\Ó[™ØØ\KBˆ^Y\”^X˜XÚÓØÚÑ[˜X›Yˆ^Y\”^X˜XÚÓØÚÑ[˜X›YBˆ[šTÚÚ\[˜X›Yˆ[šTÚÚ\[˜X›YBˆ[›Ñ‘[˜X›Yˆ[›Ñ‘[˜X›YBˆ[›Ñ\[˜X›Yˆ[›Ñ\[˜X›YBˆ[šTÚÚ\]]ÔÚÚ\ˆ[šTÚÚ\]]ÔÚÚ\BˆÚÚ\\Ñ[˜X›YˆÚÚ\\Ñ[˜X›YBˆÚÚ\\Ğ[Ø^\Õš\ÚX›NˆÚÚ\\Ğ[Ø^\Õš\ÚX›KBˆÚİÓ™^\\ÛÙP]ÛˆÚİÓ™^\\ÛÙP]Û‹BˆÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆÚİÑ\\ÛÙPœ›İÜÙ\]Û‹BˆÚİÔ^Y\”Ù\šXÙ\Ğ]ÛˆÚİÔ^Y\”Ù\šXÙ\Ğ]Û‹BˆÚİÓ™^\\ÛÙTÜİ\]ÛˆÚİÓ™^\\ÛÙTÜİ\]Û‹Bˆ™^\\ÛÙU™\ÚÛˆ™^\\ÛÙU™\ÚÛBˆ™^\\ÛÙTÚÚ\š[\‘[˜X›Yˆ™^\\ÛÙTÚÚ\š[\‘[˜X›YBˆ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›Yˆ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YBˆ^Y\•›Û[YQÙ\İ\™Q[˜X›Yˆ^Y\•›Û[YQÙ\İ\™Q[˜X›YBˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›Yˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YBˆ^Y\Ù[\•\^T]\ÙQ[˜X›Yˆ^Y\Ù[\•\^T]\ÙQ[˜X›YBˆ^Y\‘İX›U\ÙYZÑ[˜X›Yˆ^Y\‘İX›U\ÙYZÑ[˜X›YBˆ^Y\‘İX›U\ÙYZÔÙXÛÛ™Îˆ^Y\‘İX›U\ÙYZÔÙXÛÛ™ËBˆ^Y\“Ü[”İX]\Ñ[˜X›Yˆ^Y\“Ü[”İX]\Ñ[˜X›YBˆ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›Yˆ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YBˆ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›Yˆ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›YBˆ\‘›Ü™YÜ›İ[™”Îˆ\‘›Ü™YÜ›İ[™”ËBˆ\”™[™\˜XÚÙ[™ˆ\”™[™\˜XÚÙ[™Bˆ\“Y][]X[]T›Ùš[Nˆ\“Y][]X[]T›Ùš[KBˆ\•\ØØ[[™Ó[ÙNˆ\•\ØØ[[™Ó[ÙKBˆ\“™]\˜[\ØØ[\ˆ\“™]\˜[\ØØ[\‹Bˆ\“™]\˜[\ØØ[\•ˆ\“™]\˜[\ØØ[\•‹Bˆ\”^Y\”ÚÚ[ˆ\”^Y\”ÚÚ[‹Bˆ\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆ\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜ‹Bˆ\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆ\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜ‹Bˆ\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›Yˆ\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›YBˆ\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›Nˆ\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›KBˆ\”Xİ\™R[”Xİ\™Q[˜X›Yˆ\”Xİ\™R[”Xİ\™Q[˜X›YBˆ\\^]Xİ\™R[”Xİ\™Q[˜X›Yˆ\\^]Xİ\™R[”Xİ\™Q[˜X›YBˆ\’“[ÙNˆ\’“[ÙKBˆ\”İ\œ›İ[™Ûİ[™[˜X›Yˆ\”İ\œ›İ[™Ûİ[™[˜X›YBˆØ]ÚÙÙ]\‘[˜X›YˆØ]ÚÙÙ]\‘[˜X›YBˆÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YˆÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YBˆ^\š[Y[[™X]\™\Ñ[˜X›Yˆ^\š[Y[[™X]\™\Ñ[˜X›YBˆ^\š[Y[[™X]\™\Ó\İÚ[™ÙY]ˆ^\š[Y[[™X]\™\Ó\İÚ[™ÙY]Bˆ^\š[Y[[T”™[ØY[˜X›Yˆ^\š[Y[[T”™[ØY[˜X›YBˆ^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›Yˆ^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›YBˆ^\š[Y[[T”™[ØYÙ[[\‘[˜X›Yˆ^\š[Y[[T”™[ØYÙ[[\‘[˜X›YBˆ^\š[Y[[T”™[ØYÚYšS[Z]Pˆ^\š[Y[[T”™[ØYÚYšS[Z]P‹Bˆ^\š[Y[[T”™[ØYÙ[[\“[Z]Pˆ^\š[Y[[T”™[ØYÙ[[\“[Z]P‹Bˆ^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YNˆ^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YKBˆ^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜÎˆ^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜËBˆ^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\Îˆ^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\ËBˆ^\š[Y[[T”™[ØY]]ĞÛX\ˆ^\š[Y[[T”™[ØY]]ĞÛX\‹Bˆ^\š[Y[[PÛİYŞ[˜Ñ[˜X›Yˆ^\š[Y[[PÛİYŞ[˜Ñ[˜X›YBƒBˆİX]Q›Ü™YÜ›İ[™ÛÛÜˆİX]Q›Ü™YÜ›İ[™ÛÛÜ‹BˆİX]Tİ›ÚÙPÛÛÜˆİX]Tİ›ÚÙPÛÛÜ‹BˆİX]Tİ›ÚÙUÚYˆİX]Tİ›ÚÙUÚYBˆİX]Q›ÛÚ^™NˆİX]Q›ÛÚ^™KBˆİX]U™\XØ[Ù™œÙ]ˆİX]U™\XØ[Ù™œÙ]BˆİX]\Õš\ÚX›NˆİX]\Õš\ÚX›KBƒBˆÚİÒØ[™[ˆÚİÒØ[™[‹BˆYTÜ\ÚØÜ™Y[ˆYTÜ\ÚØÜ™Y[‹Bˆ[ÙTİÚ]Ú[š[X][Û‘[˜X›Yˆ[ÙTİÚ]Ú[š[X][Û‘[˜X›YBˆØ[™[]]Õ\]S[Ù[\ÎˆØ[™[]]Õ\]S[Ù[\ËBˆÙX\ÛÛ“Y[NˆÙX\ÛÛ“Y[KBˆÜš^›Û[\\ÛÙS\İˆÜš^›Û[\\ÛÙS\İBˆYYXQ]Z[]P\ÛÜšÑ[˜X›YˆYYXQ]Z[]P\ÛÜšÑ[˜X›YBˆYYXQ]Z[[\›˜]TÜİ\‘[˜X›YˆYYXQ]Z[[\›˜]TÜİ\‘[˜X›YBˆYYXQ]Z[Ú[Z[\•]\Ñ[˜X›YˆYYXQ]Z[Ú[Z[\•]\Ñ[˜X›YBˆ\ÙPÛ\ÜÚXÔØÚY[URNˆ\ÙPÛ\ÜÚXÔØÚY[URKBˆ\›Ğ˜[›™\Ø][ÙÒYˆ\›Ğ˜[›™\Ø][ÙÒYBˆ\›Ğ˜[›™\™Z]š[Üˆ\›Ğ˜[›™\™Z]š[Ü‹BˆÛYPØ][ÙÓ^[İ]İ™\œšY\ÎˆÛYPØ][ÙÓ^[İ]İ™\œšY\ËBˆÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YˆÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YBˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]NˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]KBˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]NˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]KBˆ\\™›Ü›X[˜ÙSİ™\›^Q[˜X›Yˆ\\™›Ü›X[˜ÙSİ™\›^Q[˜X›YBˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]ˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]Bˆ^\š[Y[[\›Ğ›YY]™[ˆ^\š[Y[[\›Ğ›YY]™[Bˆ^\š[Y[[ÛYPØ\™Ú\Nˆ^\š[Y[[ÛYPØ\™Ú\KBˆ^\š[Y[[][QÜ˜YY[[]Nˆ^\š[Y[[][QÜ˜YY[[]KBˆ^\š[Y[[\›ÒZYÚØØ[Nˆ^\š[Y[[\›ÒZYÚØØ[KBˆ^\š[Y[[\›Ğ›YYİ™[™İˆ^\š[Y[[\›Ğ›YYİ™[™İBˆ^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[Nˆ^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[KBˆ^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[Nˆ^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[KBˆ^\š[Y[[Ø\™˜Y]\ÔØØ[Nˆ^\š[Y[[Ø\™˜Y]\ÔØØ[KBˆ^\š[Y[[YYXPØ\™ØØ[Nˆ^\š[Y[[YYXPØ\™ØØ[KBˆ^\š[Y[[Û\ÜÔİ™[™İˆ^\š[Y[[Û\ÜÔİ™[™İBˆ^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÎˆ^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜËBˆ^\š[Y[[Ü˜YY[XØÙ[[[œÚ]Nˆ^\š[Y[[Ü˜YY[XØÙ[[[œÚ]KBˆ^\š[Y[[Ü˜YY[ØÜ›Û[İ[Ûˆ^\š[Y[[Ü˜YY[ØÜ›Û[İ[Û‹Bˆ^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœÎˆ^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœËBˆ^\š[Y[[Ü˜YY[ÛÛÜNˆ^\š[Y[[Ü˜YY[ÛÛÜKBˆ^\š[Y[[Ü˜YY[ÛÛÜˆ^\š[Y[[Ü˜YY[ÛÛÜ‹Bˆ^\š[Y[[Ü˜YY[ÛÛÜÎˆ^\š[Y[[Ü˜YY[ÛÛÜËBˆ][ÜÜ\™Tİ[Nˆ][ÜÜ\™Tİ[KBˆ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙNˆ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙKBˆ][ÜÜ\™TÛÛYÛÛÜˆ][ÜÜ\™TÛÛYÛÛÜ‹Bˆ™XY\][ÜÜ\™Tİ[Nˆ™XY\][ÜÜ\™Tİ[KBˆ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙNˆ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙKBˆ™XY\][ÜÜ\™TÛÛYÛÛÜˆ™XY\][ÜÜ\™TÛÛYÛÛÜ‹BˆYYXQ]Z[[[Y[Ü™\ˆYYXQ]Z[[[Y[Ü™\‹BˆYYXQ]Z[Y[‘[[Y[ÎˆYYXQ]Z[Y[‘[[Y[ËBˆ™XY\‘]Z[[[Y[Ü™\ˆ™XY\‘]Z[[[Y[Ü™\‹Bˆ™XY\‘]Z[Y[‘[[Y[Îˆ™XY\‘]Z[Y[‘[[Y[ËBˆYYXPÛÛ[[œÔÜ˜Z]ˆYYXPÛÛ[[œÔÜ˜Z]BˆYYXPÛÛ[[œÓ[™ØØ\NˆYYXPÛÛ[[œÓ[™ØØ\KBƒBˆ™XY[™Ó[ÙNˆ™XY[™Ó[ÙKBˆØ[™[”™XY\“[ÙNˆØ[™[”™XY\“[ÙKBˆØ[™[”™XY\“[ÙSİ™\œšY\ÎˆØ[™[”™XY\“[ÙSİ™\œšY\ËBˆ™XY\‘İÛœØ[\R[XYÙ\Îˆ™XY\‘İÛœØ[\R[XYÙ\ËBˆ™XY\Ü›Ü›Ü™\œÎˆ™XY\Ü›Ü›Ü™\œËBˆ™XY\‘\ØX›T]ZXÚĞXİ[ÛœÎˆ™XY\‘\ØX›T]ZXÚĞXİ[ÛœËBˆ™XY\‘\ØX›QİX›U\ˆ™XY\‘\ØX›QİX›U\Bˆ™XY\“]™U^ˆ™XY\“]™U^Bˆ™XY\’YP˜\œÓÛ”İÚ\Nˆ™XY\’YP˜\œÓÛ”İÚ\KBˆ™XY\˜XÚÙÜ›İ[™ÛÛÜˆ™XY\˜XÚÙÜ›İ[™ÛÛÜ‹Bˆ™XY\“ÜšY[][Ûˆ™XY\“ÜšY[][Û‹Bˆ™XY\•\›Û™\Îˆ™XY\•\›Û™\ËBˆ™XY\’[™\\›Û™\Îˆ™XY\’[™\\›Û™\ËBˆ™XY\[š[X]TYÙU˜[œÚ][ÛœÎˆ™XY\[š[X]TYÙU˜[œÚ][ÛœËBˆ™XY\•\ØØ[R[XYÙ\Îˆ™XY\•\ØØ[R[XYÙ\ËBˆ™XY\•\ØØ[SX^ZYÚˆ™XY\•\ØØ[SX^ZYÚBˆ™XY\•\ØØ[S[Ù[˜[YNˆ™XY\•\ØØ[S[Ù[˜[YKBˆ™XY\”YÙ\ÕÔ™[ØYˆ™XY\”YÙ\ÕÔ™[ØYBˆ™XY\”YÙYYÙS^[İ]ˆ™XY\”YÙYYÙS^[İ]Bˆ™XY\”YÙYYÙSÙ™œÙ]ˆ™XY\”YÙYYÙSÙ™œÙ]Bˆ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\Îˆ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ËBˆ™XY\”Ü]ÚYR[XYÙ\Îˆ™XY\”Ü]ÚYR[XYÙ\ËBˆ™XY\”™]™\œÙTÜ]Ü™\ˆ™XY\”™]™\œÙTÜ]Ü™\‹Bˆ™XY\•™\XØ[[™š[š]TØÜ›Ûˆ™XY\•™\XØ[[™š[š]TØÜ›ÛBˆ™XY\”[\˜›Şˆ™XY\”[\˜›ŞBˆ™XY\”[\˜›Ş[[İ[ˆ™XY\”[\˜›Ş[[İ[Bˆ™XY\”[\˜›ŞÜšY[][Ûˆ™XY\”[\˜›ŞÜšY[][Û‹Bˆ™XY\“ÜšY[][Û“ØÚÑ[˜X›Yˆ™XY\“ÜšY[][Û“ØÚÑ[˜X›YBˆ™XY\“ÜšY[][Û“ØÚÓX\ÚÎˆ™XY\“ÜšY[][Û“ØÚÓX\ÚËBˆ™XY\”™XY™\ÚÛ\˜Ù[ˆ™XY\”™XY™\ÚÛ\˜Ù[BƒBˆ™XY\‘›ÛÚ^™Nˆ™XY\‘›ÛÚ^™KBˆ™XY\‘›Û˜[Z[Nˆ™XY\‘›Û˜[Z[KBˆ™XY\‘›ÛÙZYÚˆ™XY\‘›ÛÙZYÚBˆ™XY\ÛÛÜ”™\Ù]ˆ™XY\ÛÛÜ”™\Ù]Bˆ™XY\•^[YÛ›Y[ˆ™XY\•^[YÛ›Y[Bˆ™XY\“[™TÜXÚ[™Îˆ™XY\“[™TÜXÚ[™ËBˆ™XY\“X\™Ú[ˆ™XY\“X\™Ú[‹BƒBˆ]]ĞÛX\ØXÚQ[˜X›Yˆ]]ĞÛX\ØXÚQ[˜X›YBˆ]]ĞÛX\ØXÚU™\ÚÛPˆ]]ĞÛX\ØXÚU™\ÚÛP‹BˆYÚ]X[]U™\ÚÛˆYÚ]X[]U™\ÚÛBˆ˜XÚÙÜ›İ[™Ô\[[™Q[˜X›Yˆ˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YBˆ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›Yˆ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YBˆ™XY\‘İÛ›ØYÕÚYšSÛ›Nˆ™XY\‘İÛ›ØYÕÚYšSÛ›KBˆ™XY\‘İÛ›ØYÔ\˜[[[Z]ˆ™XY\‘İÛ›ØYÔ\˜[[[Z]Bˆ]]Õ\]TÙ\šXÙ\Ñ[˜X›Yˆ]]Õ\]TÙ\šXÙ\Ñ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›YˆÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›YBˆÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YˆÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YˆÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÎˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYËBˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÎˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YËBˆÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙNˆÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙKBˆÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]NˆÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]KBˆÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ÎˆÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ËBˆÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YˆÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YBˆÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÎˆÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ËBˆÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÎˆÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ËBˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]NˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]KBˆÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÎˆÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ËBˆÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚˆÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚBˆÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ÎˆÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ËBˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]NˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]KBˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÎˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYËBˆÚ]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YˆÚ]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YBˆÚ]X”™[X\ÙU\]P]˜Z[X›NˆÚ]X”™[X\ÙU\]P]˜Z[X›KBˆÚ]X”™[X\ÙS]\İ™\œÚ[ÛˆÚ]X”™[X\ÙS]\İ™\œÚ[Û‹BˆÚ]X”™[X\ÙUT“ˆÚ]X”™[X\ÙUT“BˆÚ]X”™[X\ÙTÚİĞ[\[™[™ÎˆÚ]X”™[X\ÙTÚİĞ[\[™[™ËBˆÚ]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆÚ]X”™[X\ÙS\İ›Û\Y™\œÚ[Û‹Bˆš[\’Üœ›ÜÛÛ[ˆš[\’Üœ›ÜÛÛ[BˆÙ[XİYÚ[Z[\š]P[ÛÜš]NˆÙ[XİYÚ[Z[\š]P[ÛÜš]KBˆ\™›Ü›X[˜ÙS[ÙQ[˜X›Yˆ\™›Ü›X[˜ÙS[ÙQ[˜X›YBˆ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[Îˆ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ËBˆ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\Îˆ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\ËBˆØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQˆØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQBˆØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÎˆØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ËBƒBˆÛÛXİ[ÛœÎˆ˜XÚİ\ÛÛXİ[ÛœËBˆ›ÙÜ™\ÜÑ]Nˆ›ÙÜ™\ÜÑ]KBˆ˜XÚÙ\”İ]Nˆ˜XÚÙ\”İ]KBˆØ][ÙÜÎˆØ][ÙÜËBˆÙ\šXÙ\ÎˆÙ\šXÙ\ËBˆİ™[Z[ĞYÛœÎˆİ™[Z[ĞYÛœËBˆÚŞTİ™X[NˆÚŞTİ™X[KBˆ]š[ÔYÚ[œÎˆ]š[ÔYÚ[œËBˆX[™ØPÛÛXİ[ÛœÎˆX[™ØPÛÛXİ[ÛœËBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÎˆX[™ØT™XY[™Ô›ÙÜ™\ÜËBˆX[™ØPØ][ÙÜÎˆX[™ØPØ][ÙÜËBˆİ\İÛPØ][ÙÜÎˆİ\İÛPØ][ÙÜËBˆØ[™[“[Ù[\ÎˆØ[™[“[Ù[\ËBˆ™XY\‘^[œÚ[ÛœÔİ]Nˆ™XY\‘^[œÚ[ÛœÔİ]KBˆÙX\˜Ú\İÜNˆÙX\˜Ú\İÜKBˆ™XÛÛ[Y[™][ÛØXÚNˆ™XÛÛ[Y[™][Û‘[™Ú[™KœÚ\™Y™Ù]™XÛÛ[Y[™][ÛØXÚJ
KBˆ\Ù\”˜][™ÜÎˆXİ]™T˜][™ÜËœ˜][™ÜËBˆ\Ù\”˜][™Ó›İ\ÎˆXİ]™T˜][™ÜË››İ\ËBˆYYXTİ]TÙ][™ÜÎˆ˜XÚİ\]K˜Ø\\™SYYXTİ]TÙ][™ÜÊ
KBˆÙ\šXÙ\Ô™\Ù[ˆÛİ\˜ÙPØ\\™HOHš[BˆØ[™[“[Ù[\Ô™\Ù[ˆS[Ù[SX[˜YÙ\‹œÚ\™Y›Y]Y]TİÜ™Q˜Z[YÓØYBˆ
CBƒBˆ˜\ˆ˜XÚİ\Ú]›Ùš[\ÈH˜XÚİ\BƒBˆYˆ]Ù\šXÙ\ÔÙ][™ÜÈHÙ[‹˜Ø\\™TÙ\šXÙ\ÔØÛÜYÙ][™ÜÊ
HÃBˆ˜XÚİ\Ú]›Ùš[\ËœÙ\šXÙ\ÔÙ][™ÜÈHÙ\šXÙ\ÔÙ][™ÜÃBˆ˜XÚİ\Ú]›Ùš[\ËœÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YHYCBˆH[ÙHÃBˆ˜XÚİ\Ú]›Ùš[\ËœÙ\šXÙ\ÔÙ][™ÜÈHš[Bˆ˜XÚİ\Ú]›Ùš[\ËœÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YH˜[ÙCBˆCBˆ˜XÚİ\Ú]›Ùš[\ËœÚ\™\ÔÙ\šXÙ\ÈH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆ˜XÚİ\Ú]›Ùš[\Ëœ›Ùš[\ÈHHÙ[‹˜Ø\\™T›Ùš[TÛ˜\ÚİÊBˆ›Ùš[\ÎˆØ\\™PÛÛ^œ›Ùš[\ËBˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]Nˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]Nˆ]\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ[˜ÛYTš]˜]PÛİY˜XÚÙ\Ü™Y[X[Îˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ
CBˆYˆ\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\ÚİBˆ]Ø\\™YXİ]™U˜XÚÙ\ˆH˜XÚİ\Ú]›Ùš[\Ëœ›Ùš[\ÏË™š\œİ
Ú\™NˆÃBˆ	šYOHXİ]™T›Ùš[RQBˆ	‰ˆ	˜XÚÙ\”İ]UØ\ĞØ\\™YBˆ	‰ˆ	˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YBˆJHÃBˆ˜XÚİ\Ú]›Ùš[\Ë˜XÚÙ\”İ]HHØ\\™YXİ]™U˜XÚÙ\‹˜XÚÙ\”İ]CBˆCBˆ˜XÚİ\Ú]›Ùš[\Ë˜Xİ]™T›Ùš[RQHXİ]™T›Ùš[RQBƒBˆYˆ]\ÙTØY™PÛİYÚŞTİ™X[TÛ˜\Úİ[˜ÛYTš]˜]PÛİY™XÛİ™\T^[ØYÈÃBˆHÙ[‹˜Ø\\™TÚ\™YÛİ\˜ÙT^[ØYÊ[Îˆ	˜˜XÚİ\Ú]›Ùš[\ÊCBˆCBˆİX\™Xİ]™T›Ùš[TØÛÜR\Ğİ\œ™[
Ø\\™YØÛÜJH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ\ØØ\™YH˜XÚİ\Ø\\™YXÜ›ÜÜÈH›Ùš[HØÛÜHÜˆ›Üİ\ˆÚ[™ÙH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹˜Xİ]™T›Ùš[PÚ[™ÙYBˆCBˆ™]\›ˆ˜XÚİ\Ú]›Ùš[\ÃBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ\\™TÚ\™YÛİ\˜ÙT^[ØYÊ[È˜XÚİ\ˆ[›İ]˜XÚİ\]JH›İÜÈÃBˆİX\™T›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ËBˆ]Û˜\ÚİÈH˜XÚİ\œ›Ùš[\È[ÙHÈ™]\›ˆCBˆİX\™]Xİ]™T›Ùš[RQH˜XÚİ\˜Xİ]™T›Ùš[RQ[ÙHÃBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹˜Xİ]™T›Ùš[PÚ[™ÙYBˆCBˆ][˜Xİ]™TÛ˜\ÚİÈHÛ˜\ÚİË™š[\ˆÈ	šYOHXİ]™T›Ùš[RQCBˆİX\™Z[˜Xİ]™TÛ˜\ÚİËš\Ñ[\H[ÙHÈ™]\›ˆCBƒBˆ˜\ˆ™[XZ[š[™Ğ]\ÈHX^[][TÚ\™YÛİ\˜ÙT^[ØY]\ÃBˆ˜\ˆÚÚ\Y›ÜYÙ]HBƒBˆ˜\ˆÛİ™\™Y^[ØY]ÈHÙ]İš[™ÏŠ
CBˆ˜\ˆÛİ™\™Y\˜Ú]™R\Ú\ÈHÙ]İš[™ÏŠ
CBˆ˜\ˆÚŞTİ™X[T^[ØYÎˆĞ˜XÚİ\ÚŞTİ™X[TÚ\™Y^[ØYHH×CBˆ›ÜˆÛ˜\Úİ[ˆ[˜Xİ]™TÛ˜\ÚİÈÃBˆİX\™]Øİ[Y[HÛ˜\ÚİœÚŞTİ™X[Tİ]Q]KBˆ]YÚ[œÈHXÛÙYÚŞTİ™X[R[œİ[YYÚ[œÊØİ[Y[
H[ÙHÈÛÛ[YHCBˆ›ÜˆYÚ[ˆ[ˆYÚ[œÈÚ\™HÛİ™\™Y^[ØY]Ëš[œÙ\
YÚ[‹œ^[ØY™[]]™T]
Kš[œÙ\YÃBˆ]\˜Ú]™R\ÚHYÚ[‹˜\˜Ú]™TÒLM‹›İÙ\˜Ø\ÙY

CBˆ]Ø\œšY\Ğ\˜Ú]™HHXÛİ™\™Y\˜Ú]™R\Ú\Ë˜ÛÛZ[œÊ\˜Ú]™R\Ú
CBˆİX\™]^[ØYHÚ\™YÚŞTİ™X[T^[ØY
Bˆ›ÜˆYÚ[‹Bˆ[˜ÛY[™Ğ\˜Ú]™NˆØ\œšY\Ğ\˜Ú]™CBˆ
H[ÙHÈÛÛ[YHCBˆ]]PÛİ[H^[ØYœØÜš\˜Ûİ[
È
^[ØY˜\˜Ú]™OË˜Ûİ[ÏÈ
CBˆİX\™]PÛİ[H™[XZ[š[™Ğ]\È[ÙHÃBˆÚÚ\Y›ÜYÙ]
ÏHCBˆÛÛ[YCBˆCBˆ™[XZ[š[™Ğ]\ÈOH]PÛİ[BˆÚŞTİ™X[T^[ØYË˜\[™
^[ØY
CBƒBˆYˆ^[ØY˜\˜Ú]™HOHš[ÃBˆÛİ™\™Y\˜Ú]™R\Ú\Ëš[œÙ\
\˜Ú]™R\Ú
CBˆCBˆCBˆCBˆYˆ\ÚŞTİ™X[T^[ØYËš\Ñ[\HÃBˆ˜XÚİ\œÚŞTİ™X[TÚ\™Y^[ØYÈHÚŞTİ™X[T^[ØYÃBˆCBƒBˆ˜\ˆÛİ™\™Y]š[Ñš[\ÈHÙ]İš[™ÏŠ
CBˆ˜\ˆ]š[Ô^[ØYÎˆĞ˜XÚİ\]š[ÔÚ\™Y^[ØYHH×CBˆ›ÜˆÛ˜\Úİ[ˆ[˜Xİ]™TÛ˜\ÚİÈÃBˆ›ÜˆØÜ˜\\ˆ[ˆÛ˜\Úİ›]š[ÔYÚ[œÏËœØÜ˜\\œÈÏÈ×HÃBˆ]Y[]HH—
ØÜ˜\\‹œ™\ÜÚ]ÜRY
K×
ØÜ˜\\‹˜ÛÙQš[S˜[YJHƒBˆİX\™Ûİ™\™Y]š[Ñš[\Ëš[œÙ\
Y[]JKš[œÙ\YBˆ]ÛÙHH]š[ÔYÚ[”İÜ™KœÚ\™Yœ™XYÛÙJBˆ™\ÜÚ]ÜRQˆØÜ˜\\‹œ™\ÜÚ]ÜRYBˆÛÙQš[S˜[YNˆØÜ˜\\‹˜ÛÙQš[S˜[YCBˆ
H[ÙHÈÛÛ[YHCBˆ]]PÛİ[HÛÙK]˜Ûİ[BˆİX\™]PÛİ[H™[XZ[š[™Ğ]\È[ÙHÃBˆÚÚ\Y›ÜYÙ]
ÏHCBˆÛÛ[YCBˆCBˆ™[XZ[š[™Ğ]\ÈOH]PÛİ[Bˆ]š[Ô^[ØYË˜\[™
Bˆ˜XÚİ\]š[ÔÚ\™Y^[ØY
Bˆ™\ÜÚ]ÜRQˆØÜ˜\\‹œ™\ÜÚ]ÜRYBˆØÜ˜\\’QˆØÜ˜\\‹šYBˆÛÙQš[S˜[YNˆØÜ˜\\‹˜ÛÙQš[S˜[YKBˆÛÙNˆÛÙCBˆ
CBˆ
CBˆCBˆCBˆYˆ[]š[Ô^[ØYËš\Ñ[\HÃBˆ˜XÚİ\›]š[ÔÚ\™Y^[ØYÈH]š[Ô^[ØYÃBˆCBƒBˆYˆÚÚ\Y›ÜYÙ]ˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Y\ÙY[ˆ[˜ÛÛ\]H^Ü™XØ]\ÙH
ÚÚ\Y›ÜYÙ]
H[˜Xİ]™K\›Ùš[HÛİ\˜ÙH^[ØY
ÊH^ÙYYYHÚ\™Y\^[ØYYÙ]‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ›İÈ˜XÚİ\Ü™X][Û‘\œ›Ü‹œÚ\™YÛİ\˜ÙT^[ØYYÙ]^ÙYYY
ÚÚ\Y›ÜYÙ]
CBˆCBˆYˆ\ÚŞTİ™X[T^[ØYËš\Ñ[\H[]š[Ô^[ØYËš\Ñ[\HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆØ\œšYY
ÚŞTİ™X[T^[ØYË˜Ûİ[
HÚŞTİ™X[H[™
]š[Ô^[ØYË˜Ûİ[
H]š[È^[ØY
ÊH›Üˆ[˜Xİ]™H›Ùš[\È‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÚ\™YÚŞTİ™X[T^[ØY
Bˆ›ÜˆYÚ[ˆÚŞTİ™X[R[œİ[YYÚ[”İ]KBˆ[˜ÛY[™Ğ\˜Ú]™Nˆ›ÛÛBˆ
HOˆ˜XÚİ\ÚŞTİ™X[TÚ\™Y^[ØYÈÃBˆİX\™]^[ØYT“HÚ\™YÚŞTİ™X[T^[ØYT“
™[]]™T]ˆYÚ[‹œ^[ØY™[]]™T]
KBˆ]ØÜš\HOÈ]JBˆÛÛ[ÓÙˆ^[ØYT“˜\[™[™Ô]ÛÛ\Û™[
œYÚ[‹šœÈ‹\Ñ\™XİÜNˆ˜[ÙJKBˆÜ[ÛœÎˆË›X\YY”ØY™WCBˆ
KBˆØÜš\˜Ûİ[HX^[][TÚŞTİ™X[TØÜš\]\ËBˆÚLM’^
ØÜš\
K˜Ø\ÙR[œÙ[œÚ]]™PÛÛ\\™JYÚ[‹œØÜš\ÒLMŠHOH›Ü™\™YØ[YH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÛİ[›İØ\œHHÚŞTİ™X[H^[ØY›Üˆ
YÚ[‹šY
NÈ]ÈØÜš\\ÈZ\ÜÚ[™ÈÜˆÙ\È›İX]ÚH\Ú]È›Ùš[H™XÛÜ™Y‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆš[BˆCBƒBˆ˜\ˆ\˜Ú]™Nˆ]OÃBˆYˆ[˜ÛY[™Ğ\˜Ú]™KBˆ]\˜Ú]™UT“HÚ\™YÚŞTİ™X[P\˜Ú]™UT“
BˆXÚØYÙRQˆYÚ[‹šYBˆ\˜Ú]™TÒLMˆYÚ[‹˜\˜Ú]™TÒLMƒBˆ
KBˆ]]\ÈHOÈ]JÛÛ[ÓÙˆ\˜Ú]™UT“Ü[ÛœÎˆË›X\YY”ØY™WJKBˆ]\Ë˜Ûİ[HX^[][TÚŞTİ™X[P\˜Ú]™P]\ËBˆÚLM’^
]\ÊK˜Ø\ÙR[œÙ[œÚ]]™PÛÛ\\™JYÚ[‹˜\˜Ú]™TÒLMŠHOH›Ü™\™YØ[YHÃBˆ\˜Ú]™HH]\ÃBˆCBƒBˆ™]\›ˆ˜XÚİ\ÚŞTİ™X[TÚ\™Y^[ØY
BˆXÚØYÙRQˆYÚ[‹šYBˆ^[ØY™[]]™T]ˆYÚ[‹œ^[ØY™[]]™T]BˆØÜš\ÒLMˆYÚ[‹œØÜš\ÒLM‹›İÙ\˜Ø\ÙY

KBˆ\˜Ú]™TÒLMˆYÚ[‹˜\˜Ú]™TÒLM‹›İÙ\˜Ø\ÙY

KBˆØÜš\ˆØÜš\Bˆ\˜Ú]™Nˆ\˜Ú]™CBˆ
CBˆCBƒBˆš]˜]HİXİÚŞTİ™X[T\œÚ\İY[œİ[ÎˆXÛÙX›HÃBˆ][œİ[YYÚ[œÎˆÔÚŞTİ™X[R[œİ[YYÚ[”İ]WCBƒBˆ[š]
œ›ÛHXÛÙ\ˆXÛÙ\ŠH›İÜÈÃBˆ]ÛÛZ[™\ˆHHXÛÙ\‹˜ÛÛZ[™\ŠÙ^YYNˆÛÙ[™ÒÙ^\ËœÙ[ŠCBˆ[œİ[YYÚ[œÈHHÛÛZ[™\‹™XÛÙRY”™\Ù[
BˆÔÚŞTİ™X[R[œİ[YYÚ[”İ]WKœÙ[‹Bˆ›Ü’Ù^Nˆš[œİ[YYÚ[œÃBˆ
HÏÈ×CBˆCBƒBˆš]˜]H[[HÛÙ[™ÒÙ^\Îˆİš[™ËÛÙ[™ÒÙ^HÃBˆØ\ÙH[œİ[YYÚ[œÃBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈXÛÙYÚŞTİ™X[R[œİ[YYÚ[œÊÈØİ[Y[ˆ]JHOˆÔÚŞTİ™X[R[œİ[YYÚ[”İ]WOÈÃBˆİX\™Øİ[Y[˜Ûİ[H
ˆWÌ
ˆWÌBˆ]XÛÙYHOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJÚŞTİ™X[T\œÚ\İY[œİ[ËœÙ[‹œ›ÛNˆØİ[Y[
H[ÙHÃBˆ™]\›ˆš[BˆCBˆ™]\›ˆXÛÙYš[œİ[YYÚ[œÃBˆCBƒBˆš]˜]Hİ]XÈ˜\ˆÚ\™YÚŞTİ™X[T›ÛİT“ˆT“ÈÃBˆİX\™]İ\ÜHOÈš[SX[˜YÙ\‹™Y˜][\›
Bˆ›Üˆ˜\XØ][Û”İ\Ü\™XİÜKBˆ[ˆ\Ù\‘ÛXZ[“X\ÚËBˆ\›ÜšX]Q›Üˆš[BˆÜ™X]Nˆ˜[ÙCBˆ
H[ÙHÈ™]\›ˆš[CBˆ™]\›ˆİ\Ü˜\[™[™Ô]ÛÛ\Û™[
”ÚŞTİ™X[H‹\Ñ\™XİÜNˆYJKœİ[™\™^™Yš[UT“BˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÚ\™YÚŞTİ™X[T^[ØYT“
™[]]™T]ˆİš[™ÊHOˆT“ÈÃBˆİX\™]›ÛİHÚ\™YÚŞTİ™X[T›ÛİT“Bˆ\™[]]™T]š\Ñ[\KBˆ\™[]]™T]š\Ô™Yš^
‹ÈŠKBˆ\™[]]™T]˜ÛÛZ[œÊ—ŠKBˆ\™[]]™T]œÜ]
Ù\\˜]Üˆ‹ÈŠK˜ÛÛZ[œÊ‹‹ˆŠH[ÙHÈ™]\›ˆš[CBˆ]XÚØYÙT›ÛİH›ÛİBˆ˜\[™[™Ô]ÛÛ\Û™[
”XÚØYÙ\È‹\Ñ\™XİÜNˆYJCBˆœİ[™\™^™Yš[UT“Bˆ]\›H›Ûİ˜\[™[™Ô]ÛÛ\Û™[
™[]]™T]\Ñ\™XİÜNˆYJKœİ[™\™^™Yš[UT“BˆİX\™\›œ]š\Ô™Yš^
XÚØYÙT›Ûİœ]
È‹ÈŠH[ÙHÈ™]\›ˆš[CBˆ™]\›ˆ\›BˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÚ\™YÚŞTİ™X[P\˜Ú]™UT“
XÚØYÙRQˆİš[™Ë\˜Ú]™TÒLMˆİš[™ÊHOˆT“ÈÃBˆİX\™]›ÛİHÚ\™YÚŞTİ™X[T›ÛİT“BˆÚŞTİ™X[TİX›RQš\Õ˜[YXÚØYÙS˜[YJXÚØYÙRQ
KBˆ\ÔÒLM’^
\˜Ú]™TÒLMŠH[ÙHÈ™]\›ˆš[CBˆ™]\›ˆ›ÛİBˆ˜\[™[™Ô]ÛÛ\Û™[
\˜Ú]™\È‹\Ñ\™XİÜNˆYJCBˆ˜\[™[™Ô]ÛÛ\Û™[
XÚØYÙRQ\Ñ\™XİÜNˆYJCBˆ˜\[™[™Ô]ÛÛ\Û™[
—
\˜Ú]™TÒLM‹›İÙ\˜Ø\ÙY

JKœÚŞH‹\Ñ\™XİÜNˆ˜[ÙJCBˆCBƒBˆš]˜]Hİ]XÈ[˜È\ÔÒLM’^
È˜[YNˆİš[™ÊHOˆ›ÛÛÃBˆ]›Ü›X[^™YH˜[YK›İÙ\˜Ø\ÙY

CBˆ™]\›ˆ›Ü›X[^™Y˜Ûİ[OH	‰ˆ›Ü›X[^™Y˜[Ø]\ÙJš\Ò^YÚ]
CBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÚLM’^
È]Nˆ]JHOˆİš[™ÈÃBˆÒLM‹š\Ú
]Nˆ]JK›X\Èİš[™Ê›Ü›X]ˆ‰L‹	
HKš›Ú[™Y

CBˆCBƒBˆİ]XÈ[˜ÈZYÜ˜][™Ó]š[ÔÚ\™Y^[ØYÑ›Ü”™\İÜ™JBˆÈÛİ\˜ÙNˆ˜XÚİ\]KBˆÜš]PÛÙNˆ
ÈÛÙNˆİš[™ËÈ™\ÜÚ]ÜRQˆİš[™ËÈØÜ˜\\’Qˆİš[™ÊH›İÜÈOˆİš[™ÃBˆ
HOˆ]š[ÔÚ\™Y^[ØYZYÜ˜][Û”™\İ[ÃBˆ˜\ˆ˜XÚİ\HÛİ\˜ÙCBˆ˜\ˆZYÜ˜]Y^[ØYÎˆĞ˜XÚİ\]š[ÔÚ\™Y^[ØYHH×CBˆ˜\ˆZYÜ˜]Y^[ØYÛİ[HBˆ˜\ˆ™Y\ÙY^[ØYÛİ[HBˆ›Üˆ^[ØY[ˆÛİ\˜ÙK›]š[ÔÚ\™Y^[ØYÈÏÈ×HÃBˆ]YØXŞS˜[YHH]š[ÔYÚ[”İ\Ü˜ÛÙQš[S˜[YJ›Ü”ØÜ˜\\’Qˆ^[ØYœØÜ˜\\’Q
CBˆ]ÛÛ[Y™\ÜÙY˜[YHH]š[ÔYÚ[”İÜ™K˜ÛÙQš[S˜[YJBˆ›Ü”ØÜ˜\\’Qˆ^[ØYœØÜ˜\\’QBˆÛÙNˆ^[ØY˜ÛÙCBˆ
CBˆİX\™\^[ØY˜ÛÙKš\Ñ[\KBˆ^[ØY˜ÛÙK]˜Ûİ[H]š[ÔYÚ[”İÜ™K›İ[™Ë˜ÛÙP]\ËBˆ^[ØY˜ÛÙQš[S˜[YHOHYØXŞS˜[YCBˆ^[ØY˜ÛÙQš[S˜[YHOHÛÛ[Y™\ÜÙY˜[YKBˆ˜XÚİ\ÛÛZ[œÓ]š[Ô^[ØY™Y™\™[˜ÙJ˜XÚİ\^[ØYˆ^[ØY
H[ÙHÃBˆ™Y\ÙY^[ØYÛİ[
ÏHCBˆÛÛ[YCBˆCBˆ]Üš][“˜[YNˆİš[™ÃBˆÈÃBˆÜš][“˜[YHHHÜš]PÛÙJBˆ^[ØY˜ÛÙKBˆ^[ØYœ™\ÜÚ]ÜRQBˆ^[ØYœØÜ˜\\’QBˆ
CBˆHØ]ÚÃBˆ™Y\ÙY^[ØYÛİ[
ÏHCBˆÛÛ[YCBˆCBˆİX\™Üš][“˜[YHOHÛÛ[Y™\ÜÙY˜[YH[ÙHÃBˆ™Y\ÙY^[ØYÛİ[
ÏHCBˆÛÛ[YCBˆCBˆ˜\ˆ™]Üš][Ûİ[H™\XÙS]š[Ô^[ØY™Y™\™[˜Ù\ÊBˆ[ˆ	˜˜XÚİ\›]š[ÔYÚ[œËBˆ^[ØYˆ^[ØYBˆÛÙQš[S˜[YNˆÜš][“˜[YCBˆ
CBˆYˆ˜\ˆ›Ùš[\ÈH˜XÚİ\œ›Ùš[\ÈÃBˆ›Üˆ[™^[ˆ›Ùš[\Ëš[™XÙ\ÈÃBˆ™]Üš][Ûİ[
ÏH™\XÙS]š[Ô^[ØY™Y™\™[˜Ù\ÊBˆ[ˆ	œ›Ùš[\ÖÚ[™^K›]š[ÔYÚ[œËBˆ^[ØYˆ^[ØYBˆÛÙQš[S˜[YNˆÜš][“˜[YCBˆ
CBˆCBˆ˜XÚİ\œ›Ùš[\ÈH›Ùš[\ÃBˆCBˆİX\™™]Üš][Ûİ[ˆ[ÙHÃBˆ™Y\ÙY^[ØYÛİ[
ÏHCBˆÛÛ[YCBˆCBˆZYÜ˜]Y^[ØYË˜\[™
˜XÚİ\]š[ÔÚ\™Y^[ØY
Bˆ™\ÜÚ]ÜRQˆ^[ØYœ™\ÜÚ]ÜRQBˆØÜ˜\\’Qˆ^[ØYœØÜ˜\\’QBˆÛÙQš[S˜[YNˆÜš][“˜[YKBˆÛÙNˆ^[ØY˜ÛÙCBˆ
JCBˆZYÜ˜]Y^[ØYÛİ[
ÏHCBˆCBˆ˜XÚİ\›]š[ÔÚ\™Y^[ØYÈHZYÜ˜]Y^[ØYËš\Ñ[\HÈš[ˆZYÜ˜]Y^[ØYÃBˆ™]\›ˆ]š[ÔÚ\™Y^[ØYZYÜ˜][Û”™\İ[
Bˆ˜XÚİ\ˆ˜XÚİ\BˆZYÜ˜]Y^[ØYÛİ[ˆZYÜ˜]Y^[ØYÛİ[Bˆ™Y\ÙY^[ØYÛİ[ˆ™Y\ÙY^[ØYÛİ[Bˆ
CBˆCBƒBˆš]˜]Hİ]XÈ[˜È˜XÚİ\ÛÛZ[œÓ]š[Ô^[ØY™Y™\™[˜ÙJBˆÈ˜XÚİ\ˆ˜XÚİ\]KBˆ^[ØYˆ˜XÚİ\]š[ÔÚ\™Y^[ØYBˆ
HOˆ›ÛÛÃBˆYˆ]š[Ôİ]PÛÛZ[œÔ^[ØY™Y™\™[˜ÙJ˜XÚİ\›]š[ÔYÚ[œË^[ØYˆ^[ØY
HÃBˆ™]\›ˆYCBˆCBˆ™]\›ˆ˜XÚİ\œ›Ùš[\ÏË˜ÛÛZ[œÊÚ\™NˆÃBˆ]š[Ôİ]PÛÛZ[œÔ^[ØY™Y™\™[˜ÙJ	›]š[ÔYÚ[œË^[ØYˆ^[ØY
CBˆJHOHYCBˆCBƒBˆš]˜]Hİ]XÈ[˜È]š[Ôİ]PÛÛZ[œÔ^[ØY™Y™\™[˜ÙJBˆÈİ]Nˆ]š[ÔİÜ™YYÚ[œÔİ]OËBˆ^[ØYˆ˜XÚİ\]š[ÔÚ\™Y^[ØYBˆ
HOˆ›ÛÛÃBˆİ]OËœØÜ˜\\œË˜ÛÛZ[œÊÚ\™NˆÃBˆ	šYOH^[ØYœØÜ˜\\’QBˆ	‰ˆ	œ™\ÜÚ]ÜRYOH^[ØYœ™\ÜÚ]ÜRQBˆ	‰ˆ	˜ÛÙQš[S˜[YHOH^[ØY˜ÛÙQš[S˜[YCBˆJHOHYCBˆCBƒBˆ\ØØ\™X›T™\İ[Bˆš]˜]Hİ]XÈ[˜È™\XÙS]š[Ô^[ØY™Y™\™[˜Ù\ÊBˆ[ˆİ]Nˆ[›İ]]š[ÔİÜ™YYÚ[œÔİ]OËBˆ^[ØYˆ˜XÚİ\]š[ÔÚ\™Y^[ØYBˆÛÙQš[S˜[YNˆİš[™ÃBˆ
HOˆ[ÃBˆİX\™˜\ˆ™\İÜ™Yİ]HHİ]H[ÙHÈ™]\›ˆCBˆ˜\ˆ™\XÙYÛİ[HBˆ™\İÜ™Yİ]KœØÜ˜\\œÈH™\İÜ™Yİ]KœØÜ˜\\œË›X\ÈØÜ˜\\ˆ[ƒBˆİX\™ØÜ˜\\‹šYOH^[ØYœØÜ˜\\’QBˆØÜ˜\\‹œ™\ÜÚ]ÜRYOH^[ØYœ™\ÜÚ]ÜRQBˆØÜ˜\\‹˜ÛÙQš[S˜[YHOH^[ØY˜ÛÙQš[S˜[YH[ÙHÃBˆ™]\›ˆØÜ˜\\ƒBˆCBˆ™\XÙYÛİ[
ÏHCBˆ™]\›ˆ]š[ÔYÚ[”ØÜ˜\\ŠBˆYˆØÜ˜\\‹šYBˆ›İšY\’Ù^NˆØÜ˜\\‹œ›İšY\’Ù^KBˆ™\ÜÚ]ÜRYˆØÜ˜\\‹œ™\ÜÚ]ÜRYBˆ™\ÜÚ]ÜU\›ˆØÜ˜\\‹œ™\ÜÚ]ÜU\›Bˆ˜[YNˆØÜ˜\\‹›˜[YKBˆ\ØÜš\[ÛˆØÜ˜\\‹™\ØÜš\[Û‹Bˆ]]ÜˆØÜ˜\\‹˜]]Ü‹Bˆ™\œÚ[ÛˆØÜ˜\\‹™\œÚ[Û‹Bˆš[[˜[YNˆØÜ˜\\‹™š[[˜[YKBˆÛÙQš[S˜[YNˆÛÙQš[S˜[YKBˆİ\ÜY\\ÎˆØÜ˜\\‹œİ\ÜY\\ËBˆ[˜X›YˆØÜ˜\\‹™[˜X›YBˆX[šY™\İ[˜X›YˆØÜ˜\\‹›X[šY™\İ[˜X›YBˆXÛ\™\ÔÙ][™ÜÎˆØÜ˜\\‹™XÛ\™\ÔÙ][™ÜËBˆÙÛÎˆØÜ˜\\‹›ÙÛËBˆÛÛ[[™İXYÙNˆØÜ˜\\‹˜ÛÛ[[™İXYÙKBˆ›Ü›X]ÎˆØÜ˜\\‹™›Ü›X]ÃBˆ
CBˆCBˆİ]HH™\İÜ™Yİ]CBˆ™]\›ˆ™\XÙYÛİ[BˆCBƒBˆš]˜]H[˜ÈZYÜ˜][™Ó]š[ÔÚ\™Y^[ØYÑ›Ü”™\İÜ™JÈÛİ\˜ÙNˆ˜XÚİ\]JHOˆ˜XÚİ\]HÃBˆ]İÜ™HH]š[ÔYÚ[”İÜ™KœÚ\™YBˆ]ZYÜ˜][ÛˆHÙ[‹›ZYÜ˜][™Ó]š[ÔÚ\™Y^[ØYÑ›Ü”™\İÜ™JÛİ\˜ÙJHÃBˆÛÙK™\ÜÚ]ÜRQØÜ˜\\’Q[ƒBˆHİÜ™KÜš]PÛÙJBˆÛÙKBˆ™\ÜÚ]ÜRQˆ™\ÜÚ]ÜRQBˆØÜ˜\\’QˆØÜ˜\\’QBˆ
CBˆCBˆYˆZYÜ˜][Û‹›ZYÜ˜]Y^[ØYÛİ[ˆZYÜ˜][Û‹œ™Y\ÙY^[ØYÛİ[ˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆZYÜ˜]Y
ZYÜ˜][Û‹›ZYÜ˜]Y^[ØYÛİ[
H]š[ÈÚ\™Y^[ØY
ÊHÈÛÛ[XY™\ÜÙYİÜ˜YÙNÈ™Y\ÙY
ZYÜ˜][Û‹œ™Y\ÙY^[ØYÛİ[
H‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBˆ™]\›ˆZYÜ˜][Û‹˜˜XÚİ\BˆCBƒBˆš]˜]H[˜È™\İÜ™TÚ\™YÛİ\˜ÙT^[ØYÊÈ˜XÚİ\ˆ˜XÚİ\]JHÃBˆ˜\ˆ™\İÜ™YØÜš\ÈHBˆ˜\ˆ™Y\ÙY^[ØYÈHBˆ›Üˆ^[ØY[ˆ˜XÚİ\œÚŞTİ™X[TÚ\™Y^[ØYÈÏÈ×HÃBˆİX\™]^[ØYT“HÙ[‹œÚ\™YÚŞTİ™X[T^[ØYT“
Bˆ™[]]™T]ˆ^[ØYœ^[ØY™[]]™T]Bˆ
KBˆ^[ØYœØÜš\˜Ûİ[HÙ[‹›X^[][TÚŞTİ™X[TØÜš\]\ËBˆÙ[‹š\ÔÒLM’^
^[ØYœØÜš\ÒLMŠKBˆÙ[‹œÚLM’^
^[ØYœØÜš\
CBˆ˜Ø\ÙR[œÙ[œÚ]]™PÛÛ\\™J^[ØYœØÜš\ÒLMŠHOH›Ü™\™YØ[YH[ÙHÃBˆ™Y\ÙY^[ØYÈ
ÏHCBˆÛÛ[YCBˆCBƒBˆ]ØÜš\T“H^[ØYT“˜\[™[™Ô]ÛÛ\Û™[
œYÚ[‹šœÈ‹\Ñ\™XİÜNˆ˜[ÙJCBˆYˆYš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆØÜš\T“œ]
HÃBˆÈÃBˆHš[SX[˜YÙ\‹˜Ü™X]Q\™XİÜJBˆ]ˆ^[ØYT“BˆÚ][\›YYX]Q\™XİÜšY\ÎˆYCBˆ
CBˆH^[ØYœØÜš\Üš]JÎˆØÜš\T“Ü[ÛœÎˆ˜]ÛZXÊCBˆ™\İÜ™YØÜš\È
ÏHCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÛİ[›İÜš]HHÚ\™YÚŞTİ™X[H^[ØY›Üˆ
^[ØYœXÚØYÙRQ
Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆÛÛ[YCBˆCBˆCBƒBˆİX\™]\˜Ú]™HH^[ØY˜\˜Ú]™KBˆ\˜Ú]™K˜Ûİ[HÙ[‹›X^[][TÚŞTİ™X[P\˜Ú]™P]\ËBˆÙ[‹œÚLM’^
\˜Ú]™JCBˆ˜Ø\ÙR[œÙ[œÚ]]™PÛÛ\\™J^[ØY˜\˜Ú]™TÒLMŠHOH›Ü™\™YØ[YKBˆ]\˜Ú]™UT“HÙ[‹œÚ\™YÚŞTİ™X[P\˜Ú]™UT“
BˆXÚØYÙRQˆ^[ØYœXÚØYÙRQBˆ\˜Ú]™TÒLMˆ^[ØY˜\˜Ú]™TÒLMƒBˆ
KBˆYš[SX[˜YÙ\‹™š[Q^\İÊ]]ˆ\˜Ú]™UT“œ]
H[ÙHÈÛÛ[YHCBˆOÈš[SX[˜YÙ\‹˜Ü™X]Q\™XİÜJBˆ]ˆ\˜Ú]™UT“™[][™Ó\İ]ÛÛ\Û™[

KBˆÚ][\›YYX]Q\™XİÜšY\ÎˆYCBˆ
CBˆOÈ\˜Ú]™KÜš]JÎˆ\˜Ú]™UT“Ü[ÛœÎˆ˜]ÛZXÊCBˆCBƒBˆ˜\ˆ™\İÜ™Y]š[Ñš[\ÈHBˆ]]š[ÔİÜ™HH]š[ÔYÚ[”İÜ™KœÚ\™YBˆ›Üˆ^[ØY[ˆ˜XÚİ\›]š[ÔÚ\™Y^[ØYÈÏÈ×HÃBˆ]\Ù\ĞÛÛ[Y™\ÜÙY˜[YHH^[ØY˜ÛÙQš[S˜[YHOH]š[ÔYÚ[”İÜ™K˜ÛÙQš[S˜[YJBˆ›Ü”ØÜ˜\\’Qˆ^[ØYœØÜ˜\\’QBˆÛÙNˆ^[ØY˜ÛÙCBˆ
CBˆİX\™\^[ØY˜ÛÙKš\Ñ[\KBˆ^[ØY˜ÛÙK]˜Ûİ[H]š[ÔYÚ[”İÜ™K›İ[™Ë˜ÛÙP]\ËBˆ\Ù\ĞÛÛ[Y™\ÜÙY˜[YH[ÙHÃBˆ™Y\ÙY^[ØYÈ
ÏHCBˆÛÛ[YCBˆCBˆİX\™[]š[ÔİÜ™Kš\ĞÛÙJBˆ™\ÜÚ]ÜRQˆ^[ØYœ™\ÜÚ]ÜRQBˆÛÙQš[S˜[YNˆ^[ØY˜ÛÙQš[S˜[YCBˆ
H[ÙHÈÛÛ[YHCBˆÈÃBˆÈHH]š[ÔİÜ™KÜš]PÛÙJBˆ^[ØY˜ÛÙKBˆ™\ÜÚ]ÜRQˆ^[ØYœ™\ÜÚ]ÜRQBˆØÜ˜\\’Qˆ^[ØYœØÜ˜\\’QBˆ
CBˆ™\İÜ™Y]š[Ñš[\È
ÏHCBˆHØ]ÚÃBˆ™Y\ÙY^[ØYÈ
ÏHCBˆCBˆCBƒBˆYˆ™\İÜ™YØÜš\Èˆ™\İÜ™Y]š[Ñš[\Èˆ™Y\ÙY^[ØYÈˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™\İÜ™Y
™\İÜ™YØÜš\ÊHÚŞTİ™X[H[™
™\İÜ™Y]š[Ñš[\ÊH]š[ÈÚ\™Y^[ØY
ÊNÈ™Y\ÙY
™Y\ÙY^[ØYÊH‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ\\™T›Ùš[TÛ˜\ÚİÊBˆ›Ùš[\ÎˆÔ›Ùš[WKBˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]Nˆ›ÛÛBˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]Nˆ›ÛÛBˆ[˜ÛYTš]˜]PÛİY˜XÚÙ\Ü™Y[X[Îˆ›ÛÛBˆ
H›İÜÈOˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİHÃBˆH›Ùš[\Ë›X\È›Ùš[H[ƒBˆ˜\ˆÛ˜\ÚİH˜XÚİ\›Ùš[TÛ˜\Úİ
BˆYˆ›Ùš[KšYBˆ˜[YNˆ›Ùš[K›˜[YKBˆ]˜]\”Ş[X›Ûˆ›Ùš[K˜]˜]\”Ş[X›ÛBˆ]˜]\ÛÛÜ’^ˆ›Ùš[K˜]˜]\ÛÛÜ’^Bˆ]˜]\”İÑ]Nˆ›Ùš[K˜]˜]\”İÑ]KBˆ\ÒÚYÔ›Ùš[Nˆ›Ùš[Kš\ÒÚYÔ›Ùš[KBˆÜ™X]Y]ˆ›Ùš[K˜Ü™X]Y]Bˆ[’\Úˆ›Ùš[Kœ[’\ÚBˆ[Ú[™ÙY]ˆ›Ùš[Kœ[Ú[™ÙY]BˆÚYÑ›YĞÚ[™ÙY]ˆ›Ùš[KšÚYÑ›YĞÚ[™ÙY]Bˆ
CBˆYˆ]›ÙÜ™\ÜÈH›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Yœ›ÙÜ™\ÜÑ]J›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİœ›ÙÜ™\ÜÑ]HH›ÙÜ™\ÜÃBˆH[ÙHÃBˆÛ˜\Úİœ›ÙÜ™\ÜÕØ\ĞØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ›ÙÜ™\ÜÈİÜ™HÛİ[›İ™H™XYÈ]ÈØ]Ú\İÜH\ÈXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆYˆ]˜][™ÜÈH\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ˜][™ÜĞ[™›İ\Ê›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ\Ù\”˜][™ÜÈH˜][™ÜËœ˜][™ÜÃBˆÛ˜\Úİ\Ù\”˜][™Ó›İ\ÈH˜][™ÜË››İ\ÃBˆH[ÙHÃBˆÛ˜\Úİœ˜][™ÜÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ˜][™ÜÈİÜ™HÛİ[›İ™H™XYÈ]È˜][™ÜÈ\™HXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆYˆ]ÛÛXİ[ÛœÈHXœ˜\SX[˜YÙ\‹œÚ\™Y˜ÛÛXİ[ÛœÊ›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ˜ÛÛXİ[ÛœÈHÛÛXİ[ÛœË›X\
˜XÚİ\ÛÛXİ[Û‹š[š]
œ›ÛNŠJCBˆH[ÙHÃBˆÛ˜\Úİ˜ÛÛXİ[ÛœÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈXœ˜\HİÜ™HÛİ[›İ™H™XYÈ]ÈÛÛXİ[ÛœÈ\™HXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆYˆ]Ø][ÙÜÈHØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜÑ›Ü˜XÚİ\
›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ˜Ø][ÙÜÈHØ][ÙÜÃBˆH[ÙHÃBˆÛ˜\Úİ˜Ø][ÙÜÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈØ][ÙÈİÜ™HÛİ[›İ™H™XYÈ]ÈØ][ÙÈÜ™\š[™È\ÈXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\ÈY˜][È‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBƒBˆ]˜XÚÙ\”İ]HH[˜ÛYTš]˜]PÛİY˜XÚÙ\Ü™Y[X[ÃBˆÈ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y˜XÚÙ\”İ]Q›Ü”š]˜]PÛİY^Ü
Bˆ›Ü”›Ùš[Nˆ›Ùš[KšYBˆ
CBˆˆ˜XÚÙ\“X[˜YÙ\‹œÚ\™Y˜XÚÙ\”İ]J›Ü”›Ùš[Nˆ›Ùš[KšY
CBˆYˆ]˜XÚÙ\”İ]HÃBˆÛ˜\Úİ˜XÚÙ\”İ]HH[˜ÛYTš]˜]PÛİY˜XÚÙ\Ü™Y[X[ÃBˆÈ˜XÚÙ\”İ]CBˆˆÙ[‹˜XÚÙ\”İ]UÚ]İ]Ü™Y[X[Ê˜XÚÙ\”İ]JCBˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YCBˆ[˜ÛYTš]˜]PÛİY˜XÚÙ\Ü™Y[X[ÃBˆH[ÙHÃBˆÛ˜\Úİ˜XÚÙ\”İ]UØ\ĞØ\\™YH˜[ÙCBˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ˜XÚÙ\ˆİ]HÛİ[›İ™H™XYÈ]È˜XÚÙ\ˆY]Y]H\ÈXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\È\ØÛÛ›™XİY‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆÛ˜\ÚİœÙ][™ÜÈHØ\\™T›Ùš[TØÛÜYÙ][™ÜÊ›Ü”›Ùš[Nˆ›Ùš[KšY
CBƒBˆYˆ]\İÜQ]HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™YœİÜ™J›Üˆ›Ùš[KšY
K™]J›Ü’Ù^NˆœÙX\˜Ú\İÜHŠHÃBˆYˆ]]Y\šY\ÈH˜XÚİ\ÙX\˜Ú\İÜK™XÛÙY]Y\šY\Êœ›ÛNˆ\İÜQ]JHÃBˆÛ˜\ÚİœÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJ]Y\šY\Îˆ]Y\šY\ËØ\ĞØ\\™YˆYJCBˆCBˆH[ÙHÃBˆÛ˜\ÚİœÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJØ\ĞØ\\™YˆYJCBˆCBˆHØ\\™T›Ùš[TÛİ\˜Ù\ÊBˆ[Îˆ	œÛ˜\ÚİBˆ›Ùš[RQˆ›Ùš[KšYBˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]Nˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]KBˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]Nˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]CBˆ
CBˆÚYˆ[ÜÊ“ÔÊCBˆYˆ]ÛÛXİ[ÛœÈHX[™ØSXœ˜\SX[˜YÙ\‹œÚ\™Y˜ÛÛXİ[ÛœÔÛ˜\Úİ
›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ›X[™ØPÛÛXİ[ÛœÈHÛÛXİ[ÛœË›X\ÃBˆ˜XÚİ\X[™ØPÛÛXİ[ÛŠBˆYˆ	šYBˆ˜[YNˆ	›˜[YKBˆ][\Îˆ	š][\ËBˆ\ØÜš\[Ûˆ	™\ØÜš\[ÛƒBˆ
CBˆCBˆH[ÙHÃBˆÛ˜\Úİ›X[™ØPÛÛXİ[ÛœÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ™XY\ˆXœ˜\H\È[œ™XYX›NÈÛZ]Y˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆYˆ]›ÙÜ™\ÜÈHX[™ØT™XY[™Ô›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Yœ›ÙÜ™\ÜÔÛ˜\Úİ
›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜÈH›ÙÜ™\ÜËœ™YXÙJ[ÎˆÔİš[™ÎˆX[™ØT›ÙÜ™\Ü×J
JHÃBˆ	Ôİš[™Ê	KšÙ^JWHH	K˜[YCBˆCBˆH[ÙHÃBˆÛ˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜÕØ\ĞØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ™XY\ˆ›ÙÜ™\ÜÈ\È[œ™XYX›NÈÛZ]Y˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆYˆ]Ø][ÙÜÈHX[™ØPØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜÔÛ˜\Úİ
›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ›X[™ØPØ][ÙÜÈHØ][ÙÜÃBˆH[ÙHÃBˆÛ˜\Úİ›X[™ØPØ][ÙÜÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ™XY\ˆØ][ÙÜÈ\™H[œ™XYX›NÈÛZ]Y˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆYˆ]İ\İÛPØ][ÙÜÈHØ[™[İ\İÛPØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜÔÛ˜\Úİ
›Ü”›Ùš[Nˆ›Ùš[KšY
HÃBˆÛ˜\Úİ˜İ\İÛPØ][ÙÜÈHİ\İÛPØ][ÙÜÃBˆH[ÙHÃBˆÛ˜\Úİ˜İ\İÛPØ][ÙÜÕÙ\™PØ\\™YH˜[ÙCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
›Ùš[KšY
IÜÈ™XY\ˆİ\İÛHØ][ÙÜÈ\™H[œ™XYX›NÈÛZ]Y˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆÙ[™YƒBˆ™]\›ˆÛ˜\ÚİBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ\\™TÙ\šXÙ\ÔØÛÜYÙ][™ÜÊ
HOˆÔİš[™Îˆ]WOÈÃBˆ]İÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ÃBˆ]ÛXZ[“˜[YNˆİš[™ÃBˆYˆ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQÃBˆÛXZ[“˜[YHH[™K›XZ[‹˜[™RY[YšY\ˆÏÈ˜\‘XÛ\ÙHƒBˆH[ÙHÃBˆÛXZ[“˜[YHH›Ùš[TÙ][™ÜÔİÜ™KœİZ]S˜[YJ›Üˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQ
CBˆCBˆ]ÛXZ[ˆH\Ù\‘Y˜][Ëœİ[™\™œ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆÛXZ[“˜[YJHÏÈÎ—CBƒBˆ˜\ˆ™\İ[ˆÔİš[™Îˆ]WHHÎ—CBˆ›Üˆ
Ù^KÊH[ˆÛXZ[ˆÚ\™HXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœÙ\šXÙ\ÃBˆ	‰ˆP˜XÚİ\]Kš\Õ\YÜ“YØXŞT™XY\”Ûİ\˜ÙTÙ][™ÊÙ^JHÃBˆİX\™]˜[YHHİÜ™K›Øš™Xİ
›Ü’Ù^NˆÙ^JKBˆ]]HHOÈ›Ü\S\İÙ\šX[^˜][Û‹™]JBˆœ›ÛT›Ü\S\İˆ˜[YKBˆ›Ü›X]ˆ˜š[˜\KBˆÜ[ÛœÎˆBˆ
KBˆ]K˜Ûİ[HX^[][T›Ùš[TÙ][™Õ˜[YP]\È[ÙHÃBˆ™]\›ˆš[BˆCBˆ™\İ[ÚÙ^WHH]CBˆCBˆ™]\›ˆ˜XÚİ\]KœÙ\šXÙ\ÔÙ][™ÜÑ›Ü‘^\š[Y[[ÛİYŞ[˜Ê™\İ[
CBˆCBƒBˆÚYˆ[ÜÊ“ÔÊCBˆİ]XÈ[˜ÈØ\\™T™XY\‘^[œÚ[Û”İ]JBˆY]Y]TİÜ™Nˆ\Ù\‘Y˜][ËBˆ™Y™\™[˜ÙTİÜ™Nˆ\Ù\‘Y˜][ÃBˆ
H›İÜÈOˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]HÃBˆH˜XÚİ\™XY\‘^[œÚ[Û”İ]K˜Ø\\™JBˆœ›ÛNˆY]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™Nˆ™Y™\™[˜ÙTİÜ™CBˆ
CBˆCBƒBˆËËÈ\Y\È[\İY™XY\ˆ˜XÚİ\Y]Y]H˜[œØXİ[Û˜[KˆH™Z™XİYBˆËËÈ[˜ÛÛZ[™È^[ØY\È›İ]šY[˜ÙH]H[™XYK]™\šYšYYØØ[İÜ™CBˆËËÈ\ÈÛÜœ\ÛÈ\È]]\İ™]™\ˆÙ]HYØXŞHZYÜ˜][Ûˆ]X\˜[[™CBˆËËÈ]Ø]\È™XY\ˆ[™ÛÛ\]YÙ™›[™HİÛ›ØYÈ]İ\\ƒBˆ\ØØ\™X›T™\İ[Bˆİ]XÈ[˜È™\İÜ™T™XY\‘^[œÚ[Û”İ]T™\Ù\š[™ÓØØ[Û‘˜Z[\™JBˆÈİ]Nˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]KBˆY]Y]TİÜ™Nˆ\Ù\‘Y˜][ËBˆ™Y™\™[˜ÙTİÜ™Nˆ\Ù\‘Y˜][ËBˆÛÛ^ˆİš[™ËBˆÜİ™\İÜ™U™\šYšXØ][Ûˆ


H›İÜÈOˆ›ÚY
OÈHš[Bˆ
HOˆ›ÛÛÃBˆÈÃBˆHİ]Kœ™\İÜ™JBˆÎˆY]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™Nˆ™Y™\™[˜ÙTİÜ™KBˆÜİ™\İÜ™U™\šYšXØ][ÛˆÜİ™\İÜ™U™\šYšXØ][ÛƒBˆ
CBˆ™]\›ˆYCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Z™XİY™XY\ˆ^[œÚ[ÛˆY]Y]H›Üˆ
ÛÛ^
NÈ^\İ[™ÈØØ[™XY\ˆİ]HØ\È™\Ù\™Y‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBˆÙ[™YƒBƒBˆš]˜]H[˜È™\İÜ™T›Ùš[TÛİ\˜Ù\ÊBˆÈÛ˜\Úİˆ˜XÚİ\›Ùš[TÛ˜\ÚİBˆ[ÈİÜ™Nˆ\Ù\‘Y˜][ËBˆ›Ùš[RQˆURQBˆ™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]Nˆ›ÛÛH˜[ÙCBˆ
HOˆ›ÛÛÃBƒBˆ]İ\œ™[]š[Ôİ]HH™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]CBˆÈ]š[ÔYÚ[”İÜ™JY˜][ÎˆİÜ™JK›ØY

CBˆˆš[Bˆ]]š[Ô™\İÜ™T[ˆHÛ˜\Úİ›]š[ÔYÚ[œË›X\È[˜ÛÛZ[™È[ƒBˆİX\™]İ\œ™[]š[Ôİ]H[ÙHÃBˆ™]\›ˆ^\š[Y[[ÛİY]š[Ô™\İÜ™T[ŠBˆİ]Nˆ[˜ÛÛZ[™ËBˆ]šXÙSØØ[Ûİ\˜ÙRQÎˆ×CBˆ
CBˆCBˆ™]\›ˆ˜XÚİ\]K›]š[Ô™\İÜ™T[‘›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆ[˜ÛÛZ[™Îˆ[˜ÛÛZ[™ËBˆİ\œ™[ˆİ\œ™[]š[Ôİ]CBˆ
CBˆCBˆ]™\Ù\™Y]šXÙSØØ[]š[ÔÛİ\˜ÙRQÎˆÙ]İš[™ÏƒBˆYˆ]]š[Ô™\İÜ™T[ˆÃBˆ™\Ù\™Y]šXÙSØØ[]š[ÔÛİ\˜ÙRQÈH]š[Ô™\İÜ™T[‹™]šXÙSØØ[Ûİ\˜ÙRQÃBˆH[ÙHYˆ]İ\œ™[]š[Ôİ]HÃBˆËÈHZ\ÜÚ[™ÈØ\\™YÛXZ[ˆ\È›ÈÛİ\˜ÙKY[][Ûˆ]]Üš]KƒBˆ™\Ù\™Y]šXÙSØØ[]š[ÔÛİ\˜ÙRQÈHÙ]
Bˆİ\œ™[]š[Ôİ]Kœ™\ÜÚ]ÜšY\Ë›X\
šY
CBˆ
Èİ\œ™[]š[Ôİ]KœØÜ˜\\œË›X\
šY
CBˆ
CBˆH[ÙHÃBˆ™\Ù\™Y]šXÙSØØ[]š[ÔÛİ\˜ÙRQÈH×CBˆCBƒBˆÙ[‹œ™\İÜ™TÙ\šXÙ\ÔÙ][™ÜÊBˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜËBˆØ\\™YÛÛ\][NˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YBˆÎˆİÜ™KBˆ™\Ù\š[™Îˆ™\Ù\™Y]šXÙSØØ[]š[ÔÛİ\˜ÙRQÃBˆ
CBƒBˆYˆ]]š[ÈH]š[Ô™\İÜ™T[Ëœİ]KBˆ][˜ÛÙYHOÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJ]š[ÊHÃBˆİÜ™KœÙ]
[˜ÛÙY›Ü’Ù^Nˆ›]š[ÔYÚ[œÔİ]KŒˆŠCBˆCBƒBˆYˆ]ÚŞTİ™X[HHÛ˜\ÚİœÚŞTİ™X[KÚŞTİ™X[Kš\ÔØY™PÛİYÛ˜\ÚİÃBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹™]Q[˜ÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBˆYˆ][˜ÛÙYHOÈ[˜ÛÙ\‹™[˜ÛÙJÚŞTİ™X[JK[˜ÛÙY˜Ûİ[HLÌÌÃBˆİÜ™KœÙ]
[˜ÛÙY›Ü’Ù^NˆÚŞTİ™X[TYÚ[“X[˜YÙ\‹œ[™[™ÔØY™PÛİYÛ˜\ÚİÙ^JCBˆCBˆCBƒBˆ]™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH™\İÜ™T›Ùš[T™XY\ÛÛ™šYİ\˜][ÛŠBˆÛ˜\ÚİBˆ[ÎˆİÜ™KBˆ›Ùš[RQˆ›Ùš[RQBˆ
CBƒBˆİX\™]Ù\šXÙ\ÈHÛ˜\ÚİœÙ\šXÙ\Ë]YÛœÈHÛ˜\Úİœİ™[Z[ĞYÛœÈ[ÙHÃBˆ™]\›ˆ™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆCBƒBˆYˆ›Ùš[RQOH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQÃBˆ™\İÜ™PXİ]™T›Ùš[TÛİ\˜Ù\ÊÙ\šXÙ\ÎˆÙ\šXÙ\ËYÛœÎˆYÛœÊCBˆ™]\›ˆ™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆCBƒBˆÙ\šXÙTİÜ™TØÛÜKœ™\İÜ™TÛİ\˜Ù\ÊBˆÙ\šXÙ\ÎˆÙ\šXÙ\Ë›X\ÃBˆÙ\šXÙTİÜ™TØÛÜK”™\İÜ™YÙ\šXÙJBˆYˆ	šYBˆ\›ˆ	\›BˆœÛÛ“Y]Y]Nˆ	šœÛÛ“Y]Y]KBˆœÔØÜš\ˆ	šœÔØÜš\Bˆ\ĞXİ]™Nˆ	š\ĞXİ]™KBˆÛÜ[™^ˆ	œÛÜ[™^Bˆ
CBˆKBˆYÛœÎˆYÛœË›X\ÃBˆÙ\šXÙTİÜ™TØÛÜK”™\İÜ™YYÛŠBˆYˆ	šYBˆÛÛ™šYİ\™YT“ˆ	˜ÛÛ™šYİ\™YT“BˆX[šY™\İ”ÓÓˆ	›X[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™Nˆ	š\ĞXİ]™KBˆÛÜ[™^ˆ	œÛÜ[™^Bˆ
CBˆKBˆÚŞTİ™X[Tİ]Q]NˆÛ˜\ÚİœÚŞTİ™X[Tİ]Q]KBˆ›Ü”›Ùš[Nˆ›Ùš[RQBˆ
CBˆ™]\›ˆ™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆCBƒBˆš]˜]H[˜È™\İÜ™T›Ùš[T™XY\ÛÛ™šYİ\˜][ÛŠBˆÈÛ˜\Úİˆ˜XÚİ\›Ùš[TÛ˜\ÚİBˆ[ÈİÜ™Nˆ\Ù\‘Y˜][ËBˆ›Ùš[RQˆURQBˆ\›Z]Õ[œ›Üİ\™Y›Ùš[Nˆ›ÛÛH˜[ÙCBˆ
HOˆ›ÛÛÃBˆÚYˆ[ÜÊ“ÔÊCBˆİX\™]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÔ™XY\ˆ[ÙHÈ™]\›ˆYHCBˆ]™XY\“Y]Y]TİÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆÈ\Ù\‘Y˜][Ëœİ[™\™BˆˆİÜ™CBˆİX\™]™XY\”İ]HHÛ˜\Úİœ™XY\‘^[œÚ[ÛœÔİ]CBˆÏÈÛ˜\Úİ˜ZYÚİTİ]K›X\
˜XÚİ\™XY\‘^[œÚ[Û”İ]K›ZYÜ˜][™ÓYØXŞPZYÚİJH[ÙHÃBˆ™]\›ˆÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HOHš[BˆCBˆİX\™]˜]ĞÛÛ™šYİ\˜][Û‘]HHÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]H[ÙHÃBˆ™]\›ˆÙ[‹œ™\İÜ™T™XY\‘^[œÚ[Û”İ]T™\Ù\š[™ÓØØ[Û‘˜Z[\™JBˆ™XY\”İ]KBˆY]Y]TİÜ™Nˆ™XY\“Y]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™NˆİÜ™KBˆÛÛ^ˆœ›Ùš[H
›Ùš[RQ
HƒBˆ
CBˆCBˆİX\™]ÛÛ™šYİ\˜][Û‘]HH˜XÚİ\›Ùš[TÛ˜\ÚİBˆ˜›İ[™Y™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]J˜]ĞÛÛ™šYİ\˜][Û‘]JH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Z™XİY™XY\ˆš]˜]KXÛİYÛÛ™šYİ\˜][Ûˆ›Üˆ›Ùš[H
›Ùš[RQ
NÈ^\İ[™ÈØØ[™XY\ˆÛÛ™šYİ\˜][ÛˆØ\È™\Ù\™Y‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆ˜\ˆÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH˜[ÙCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆÈÃBˆ]ÛÛ™šYİ\˜][ÛˆHH”ÓÓ‘XÛÙ\Š
K™XÛÙJBˆ™XY\‘^[œÚ[Û”š]˜]PÛİYÛÛ™šYİ\˜][Û‹œÙ[‹Bˆœ›ÛNˆÛÛ™šYİ\˜][Û‘]CBˆ
CBˆ]™]š[İ\ÔÛİ\˜Ù\ÈHH™XY\‘^[œÚ[Û”\œÚ\İ[˜ÙCBˆ˜\Z[™Ô™Y™\™[˜ÙSİ™\›^JBˆÎˆ™XY\‘^[œÚ[Û”\œÚ\İ[˜ÙK›ØY[œİ[YÛİ\˜Ù\ÊBˆœ›ÛNˆ™XY\“Y]Y]TİÜ™CBˆ
KBˆœ›ÛNˆİÜ™CBˆ
CBˆ]™\İÜ™YHÙ[‹œ™\İÜ™T™XY\‘^[œÚ[Û”İ]T™\Ù\š[™ÓØØ[Û‘˜Z[\™JBˆ™XY\”İ]KBˆY]Y]TİÜ™Nˆ™XY\“Y]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™NˆİÜ™KBˆÛÛ^ˆœ›Ùš[H
›Ùš[RQ
H‹BˆÜİ™\İÜ™U™\šYšXØ][ÛˆÃBˆH™XY\‘^[œÚ[Û”\œÚ\İ[˜ÙK˜\Tš]˜]PÛİYÛÛ™šYİ\˜][ÛŠBˆÛÛ™šYİ\˜][Û‹Bˆ›Ùš[RQˆ›Ùš[RQBˆY]Y]TİÜ™Nˆ™XY\“Y]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™NˆİÜ™KBˆ™]š[İ\ÔÛİ\˜Ù\Îˆ™]š[İ\ÔÛİ\˜Ù\ËBˆÜİ]]][Û•™\šYšXØ][ÛˆÃBˆİX\™™XY\“Y]Y]TİÜ™KœŞ[˜Ú›Ûš^™J
KBˆİÜ™KœŞ[˜Ú›Ûš^™J
KBˆ\Ù\‘Y˜][Ëœİ[™\™œŞ[˜Ú›Ûš^™J
H[ÙHÃBˆ›İÈ™XY\‘^[œÚ[Û‘\œ›Ü‹œ\œÚ\İ[˜ÙQ˜Z[Y
Bˆ”™XY\ˆš]˜]KXÛİY™\İÜ™HØ\È›İ\œÚ\İYƒBˆ
CBˆCBˆCBˆ
CBˆCBˆ
CBˆÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH™\İÜ™YBˆİX\™™\İÜ™Y\\›Z]Õ[œ›Üİ\™Y›Ùš[KBˆ›Ùš[RQOH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQ[ÙHÈ™]\›ˆCBˆÈÃBˆÈHH™XY\‘^[œÚ[Û“X[˜YÙ\‹œÚ\™Yœ™[ØYY\‘^\›˜[™\İÜ™J
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™\İÜ™Y™XY\ˆš]˜]KXÛİYÛÛ™šYİ\˜][Ûˆ›Üˆ›Ùš[H
›Ùš[RQ
K]HXİ]™H™XY\ˆİ]HÛİ[›İ™[ØY‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Z™XİY™XY\ˆš]˜]KXÛİYÛÛ™šYİ\˜][Ûˆ›Üˆ›Ùš[H
›Ùš[RQ
NÈ^\İ[™ÈØØ[™XY\ˆÛÛ™šYİ\˜][ÛˆØ\È™\Ù\™Y‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆCBˆCBˆ™]\›ˆÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆÙ[ÙCBˆ™]\›ˆYCBˆÙ[™YƒBˆCBƒBˆš]˜]H[˜È™\İÜ™PXİ]™T›Ùš[TÛİ\˜Ù\ÊBˆÙ\šXÙ\ÎˆĞ˜XÚİ\Ù\šXÙWKBˆYÛœÎˆĞ˜XÚİ\İ™[Z[ĞYÛ—CBˆ
HÃBˆ]Ù\šXÙTİÜ™HHÙ\šXÙTİÜ™KœÚ\™YBˆ›Üˆ^\İ[™È[ˆÙ\šXÙTİÜ™K™Ù]Ù\šXÙ\Ê
HÃBˆÙ\šXÙTİÜ™Kœ™[[İ™J^\İ[™ÊCBˆCBˆ›Üˆ
[™^Ù\šXÙJH[ˆÙ\šXÙ\Ë™[[Y\˜]Y

HÃBƒBˆİX\™]ØÜš\HÙ\šXÙTİÜ™TØÛÜKœÙXİ\™YØÜš\›Ü”™\İÜ™JBˆÙ\šXÙKšœÔØÜš\BˆÙ\šXÙRQˆÙ\šXÙKšYBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆ
H[ÙHÈÛÛ[YHCBˆÙ\šXÙTİÜ™KœİÜ™TÙ\šXÙJBˆYˆÙ\šXÙKšYBˆ\›ˆÙ\šXÙK\›BˆœÛÛ“Y]Y]NˆÙ\šXÙKšœÛÛ“Y]Y]KBˆœÔØÜš\ˆØÜš\Bˆ\ĞXİ]™NˆÙ\šXÙKš\ĞXİ]™KBˆÛÜ[™^ˆ[
[™^
CBˆ
CBˆCBƒBˆ]İ™[Z[ÔİÜ™HHİ™[Z[ĞYÛ”İÜ™KœÚ\™YBˆİ™[Z[ÔİÜ™Kœ™[[İ™P[

CBˆ›Üˆ
[™^YÛŠH[ˆYÛœË™[[Y\˜]Y

HÃBƒBˆİX\™Tİ™[Z[ĞÛÛ™šYİ\™YT“˜][š\Õ[œ™\ÛÛ™Y™Y™\™[˜ÙJYÛ‹˜ÛÛ™šYİ\™YT“
H[ÙHÃBˆÛÛ[YCBˆCBˆİX\™]X[šY™\İ]HHYÛ‹›X[šY™\İ”ÓÓ‹™]J\Ú[™Îˆ]
KBˆ]X[šY™\İHOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJİ™[Z[ÓX[šY™\İœÙ[‹œ›ÛNˆX[šY™\İ]JKBˆX[šY™\İœİ\ÜÒ[œİ[X›T™\Ûİ\˜Ù\È[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ”ÚÚ\[™È[˜[Yİ™[Z[ÈYÛˆœ›ÛH›Ùš[HÛ˜\Úİˆ
YÛ‹šY
H‹\Nˆ”İ™[Z[ÈŠCBˆÛÛ[YCBˆCBˆİ™[Z[ÔİÜ™KœİÜ™PYÛŠBˆYˆYÛ‹šYBˆÛÛ™šYİ\™YT“ˆYÛ‹˜ÛÛ™šYİ\™YT“BˆX[šY™\İ”ÓÓˆYÛ‹›X[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™NˆYÛ‹š\ĞXİ]™KBˆÛÜ[™^ˆ[
[™^
CBˆ
CBˆCBƒBˆ\ÚÈÈXZ[XİÜˆ[ƒBˆÙ\šXÙSX[˜YÙ\‹œÚ\™Y›ØYÙ\šXÙ\Ñœ›ÛPÛİY

CBˆİ™[Z[ĞYÛ“X[˜YÙ\‹œÚ\™Y›ØYYÛœÊ
CBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ\\™T›Ùš[TÛİ\˜Ù\ÊBˆ[ÈÛ˜\Úİˆ[›İ]˜XÚİ\›Ùš[TÛ˜\ÚİBˆ›Ùš[RQˆURQBˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]Nˆ›ÛÛBˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]Nˆ›ÛÛBˆ
H›İÜÈÃBˆ]İÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™YœİÜ™J›Üˆ›Ùš[RQ
CBˆÚYˆ[ÜÊ“ÔÊCBˆÈÃBˆ]™XY\“Y]Y]TİÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆÈ\Ù\‘Y˜][Ëœİ[™\™BˆˆİÜ™CBˆÛ˜\Úİœ™XY\‘^[œÚ[ÛœÔİ]HHHØ\\™T™XY\‘^[œÚ[Û”İ]JBˆY]Y]TİÜ™Nˆ™XY\“Y]Y]TİÜ™KBˆ™Y™\™[˜ÙTİÜ™NˆİÜ™CBˆ
CBˆHØ]ÚÃBˆYˆ™\]Z\™T™XYX›T™XY\‘^[œÚ[Û“Y]Y]HÃBˆ›İÈ\œ›ÜƒBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\ˆ›Ùš[H
›Ùš[RQ
IÜÈ™XY\ˆ^[œÚ[ÛˆY]Y]H\È[œ™XYX›NÈÛZ]Yœ›ÛHÛİYÛ˜\Úİ‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆYˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]HÃBˆ˜\ˆÛÛ™šYİ\˜][Û‘]Nˆ]OÃBˆ˜XÚİ\X[˜YÙ\‹œÚ\™Yœ\™›Ü›SÛ“XZ[•™XYÃBˆXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆÈÃBˆ]ÛÛ™šYİ\˜][ÛˆHH™XY\‘^[œÚ[Û“X[˜YÙ\‹œÚ\™YBˆ˜Ø\\™Tš]˜]PÛİYÛÛ™šYİ\˜][ÛŠ›Üˆ›Ùš[RQ
CBˆ][˜ÛÙ\ˆH”ÓÓ‘[˜ÛÙ\Š
CBˆ[˜ÛÙ\‹›İ]]›Ü›X][™ÈHËœÛÜYÙ^\×CBˆÛÛ™šYİ\˜][Û‘]HH˜XÚİ\›Ùš[TÛ˜\ÚİBˆ˜›İ[™Y™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]JBˆH[˜ÛÙ\‹™[˜ÛÙJÛÛ™šYİ\˜][ÛŠCBˆ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\ˆ›Ùš[H
›Ùš[RQ
IÜÈ™XY\ˆš]˜]KXÛİYÛÛ™šYİ\˜][Ûˆ\È[œ™XYX›NÈÛZ]Y˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆCBˆCBˆÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HHÛÛ™šYİ\˜][Û‘]CBˆCBˆÙ[™YƒBˆİX\™T›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\È[ÙHÈ™]\›ˆCBƒBˆ\X[X\ÈØ\\™YÛİ\˜Ù\ÈH
BˆÙ\šXÙ\ÎˆĞ˜XÚİ\Ù\šXÙWKBˆYÛœÎˆĞ˜XÚİ\İ™[Z[ĞYÛ—KBˆÚŞTİ™X[Tİ]Nˆ]OËBˆÚŞTİ™X[Tİ]UØ\ĞØ\\™Yˆ›ÛÛBˆ
CBˆ]Ø\\™YHÙ\šXÙTİÜ™TØÛÜKÚ]™XYÛ›TİÜ™J›Ü”›Ùš[Nˆ›Ùš[RQ
HÈÛÛ^Oˆ™\İ[Ø\\™YÛİ\˜Ù\Ë\œ›Üˆ[ƒBˆ™\İ[ÃBˆ]Ù\šXÙT™\]Y\İH”Ñ™]Ú™\]Y\İ”ÓX[˜YÙYØš™XİŠ[]S˜[YNˆ”Ù\šXÙQ[]HŠCBˆ]Ù\šXÙQ[]Y\ÈHHÛÛ^™™]Ú
Ù\šXÙT™\]Y\İ
CBˆ˜\ˆÙ\šXÙT›İÜÕÙ\™PÛÛ\]HHYCBˆ]Ù\šXÙ\ÈHÙ\šXÙQ[]Y\Ë˜ÛÛ\XİX\È[]HOˆ˜XÚİ\Ù\šXÙOÈ[ƒBˆİX\™]YH[]K˜[YJ›Ü’Ù^NˆšYŠH\ÏÈURQ[ÙHÃBˆÙ\šXÙT›İÜÕÙ\™PÛÛ\]HH˜[ÙCBˆ™]\›ˆš[BˆCBˆ™]\›ˆ˜XÚİ\Ù\šXÙJBˆYˆYBˆ\›ˆ[]K˜[YJ›Ü’Ù^Nˆ\›ŠH\ÏÈİš[™ÈÏÈˆ‹BˆœÛÛ“Y]Y]Nˆ[]K˜[YJ›Ü’Ù^NˆšœÛÛ“Y]Y]HŠH\ÏÈİš[™ÈÏÈˆ‹BˆœÔØÜš\ˆ[]K˜[YJ›Ü’Ù^NˆšœÔØÜš\ŠH\ÏÈİš[™ÈÏÈˆ‹Bˆ\ĞXİ]™Nˆ[]K˜[YJ›Ü’Ù^Nˆš\ĞXİ]™HŠH\ÏÈ›ÛÛÏÈYKBˆÛÜ[™^ˆ[]K˜[YJ›Ü’Ù^NˆœÛÜ[™^ŠH\ÏÈ[ÏÈBˆ
CBˆCBƒBˆ]YÛ”™\]Y\İH”Ñ™]Ú™\]Y\İ”ÓX[˜YÙYØš™XİŠ[]S˜[YNˆ”İ™[Z[ĞYÛ‘[]HŠCBˆ]YÛ‘[]Y\ÈHHÛÛ^™™]Ú
YÛ”™\]Y\İ
CBˆ˜\ˆYÛ”›İÜÕÙ\™PÛÛ\]HHYCBˆ]YÛœÈHYÛ‘[]Y\Ë˜ÛÛ\XİX\È[]HOˆ˜XÚİ\İ™[Z[ĞYÛÈ[ƒBˆİX\™]YH[]K˜[YJ›Ü’Ù^NˆšYŠH\ÏÈURQ[ÙHÃBˆYÛ”›İÜÕÙ\™PÛÛ\]HH˜[ÙCBˆ™]\›ˆš[BˆCBˆ]\œÚ\İYH[]K˜[YJ›Ü’Ù^Nˆ˜ÛÛ™šYİ\™YT“ŠH\ÏÈİš[™ÈÏÈˆƒBˆ]ÛÛ™šYİ\™YT“Hİ™[Z[ĞÛÛ™šYİ\™YT“˜][œ™\ÛÛ™JBˆYÛ’QˆYBˆ\œÚ\İYT“ˆ\œÚ\İYBˆ›Ùš[RQˆ›Ùš[RQBˆ
CBˆİX\™Tİ™[Z[ĞÛÛ™šYİ\™YT“˜][š\Õ[œ™\ÛÛ™Y™Y™\™[˜ÙJÛÛ™šYİ\™YT“
H[ÙHÃBˆYÛ”›İÜÕÙ\™PÛÛ\]HH˜[ÙCBˆ™]\›ˆš[BˆCBˆ™]\›ˆ˜XÚİ\İ™[Z[ĞYÛŠBˆYˆYBˆÛÛ™šYİ\™YT“ˆÛÛ™šYİ\™YT“BˆX[šY™\İ”ÓÓˆ[]K˜[YJ›Ü’Ù^Nˆ›X[šY™\İ”ÓÓˆŠH\ÏÈİš[™ÈÏÈˆ‹Bˆ\ĞXİ]™Nˆ[]K˜[YJ›Ü’Ù^Nˆš\ĞXİ]™HŠH\ÏÈ›ÛÛÏÈYKBˆÛÜ[™^ˆ[]K˜[YJ›Ü’Ù^NˆœÛÜ[™^ŠH\ÏÈ[ÏÈBˆ
CBˆCBˆİX\™Ù\šXÙT›İÜÕÙ\™PÛÛ\]KBˆYÛ”›İÜÕÙ\™PÛÛ\]KBˆÙ\šXÙ\Ë˜Ûİ[OHÙ\šXÙQ[]Y\Ë˜Ûİ[BˆYÛœË˜Ûİ[OHYÛ‘[]Y\Ë˜Ûİ[[ÙHÃBˆ›İÈÛØÛØQ\œ›ÜŠ˜ÛÙ\’[˜[Y˜[YJCBˆCBƒBˆ]İ]T™\]Y\İH”Ñ™]Ú™\]Y\İ”ÓX[˜YÙYØš™XİŠ[]S˜[YNˆ”ÚŞTİ™X[Tİ]Q[]HŠCBˆİ]T™\]Y\İœ™YXØ]HH”Ô™YXØ]J›Ü›X]ˆšYOH	P‹ÚŞTİ™X[Tİ]Q[]KœÚ[™Û]Û’Q
CBˆİ]T™\]Y\İ™™]Ú[Z]HCBˆ]İ]Q[]HHHÛÛ^™™]Ú
İ]T™\]Y\İ
K™š\œİBˆ]ÚŞTİ™X[Tİ]Nˆ]OÃBˆ]ÚŞTİ™X[Tİ]UØ\ĞØ\\™Yˆ›ÛÛBˆYˆİ]Q[]HOHš[ÃBˆÚŞTİ™X[Tİ]HHš[BˆÚŞTİ™X[Tİ]UØ\ĞØ\\™YHYCBˆH[ÙHYˆ]œÛÛˆHİ]Q[]OË˜[YJ›Ü’Ù^NˆšœÛÛ”İ]HŠH\ÏÈİš[™ËBˆ]]HHœÛÛ‹™]J\Ú[™Îˆ]
KBˆ]K˜Ûİ[H
ˆWÌ
ˆWÌÃBˆÚŞTİ™X[Tİ]HH]CBˆÚŞTİ™X[Tİ]UØ\ĞØ\\™YHYCBˆH[ÙHÃBˆÚŞTİ™X[Tİ]HHš[BˆÚŞTİ™X[Tİ]UØ\ĞØ\\™YH˜[ÙCBˆCBˆ™]\›ˆ
BˆÙ\šXÙ\ËBˆYÛœËBˆÚŞTİ™X[Tİ]KBˆÚŞTİ™X[Tİ]UØ\ĞØ\\™YBˆ
CBˆCBˆCBƒBˆYˆØ\ÙHœİXØÙ\ÜÊ]˜[Y\ÊOÈHØ\\™YÃBˆÛ˜\ÚİœÙ\šXÙ\ÈH˜[Y\ËœÙ\šXÙ\ÃBˆÛ˜\Úİœİ™[Z[ĞYÛœÈH˜[Y\Ë˜YÛœÃBˆÛ˜\ÚİœÚŞTİ™X[Tİ]Q]HH˜[Y\ËœÚŞTİ™X[Tİ]CBˆYˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]KBˆ]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÔÚŞTİ™X[TYÚ[œËBˆ˜[Y\ËœÚŞTİ™X[Tİ]UØ\ĞØ\\™YÃBˆYˆ]İ]Q]HH˜[Y\ËœÚŞTİ™X[Tİ]HÃBˆ˜\ˆØY™TÛ˜\ÚİˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİÃBˆ]Ø\\™HHÃBˆXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆØY™TÛ˜\ÚİHÚŞTİ™X[TYÚ[“X[˜YÙ\‹˜ÛÛ\]Tš]˜]PÛİYY]Y]TÛ˜\Úİ
Bˆœ›ÛT\œÚ\İYİ]Q]Nˆİ]Q]CBˆ
CBˆCBˆCBˆYˆ™XYš\ÓXZ[•™XYÃBˆØ\\™J
CBˆH[ÙHÃBˆ\Ü]Ú]Y]YK›XZ[‹œŞ[˜Ê^Xİ]NˆØ\\™JCBˆCBˆÛ˜\ÚİœÚŞTİ™X[HHØY™TÛ˜\ÚİBˆH[ÙHÃBˆÛ˜\ÚİœÚŞTİ™X[HHÚŞTİ™X[P˜XÚİ\Û˜\Úİ
Bˆ™\ÜÚ]ÜšY\Îˆ×KBˆYÚ[œÎˆ×KBˆÜ™X]Y]ˆ]J[YR[\˜[Ú[˜ÙLNMÌˆ
KBˆ\ÔØY™PÛİYÛ˜\ÚİˆYKBˆš]˜]PÛİYÛÛ™šYİ\˜][Û’\ĞÛÛ\]NˆYCBˆ
CBˆCBˆCBˆH[ÙHÃBˆYˆØ\ÙH™˜Z[\™J]\œ›ÜŠOÈHØ\\™YÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\ˆÛİ\˜ÙH™]Ú˜Z[Y›Üˆ›Ùš[H
›Ùš[RQ
Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\ˆÛİ[›İ™XYHÙ\šXÙ\È]X˜\ÙH›Üˆ›Ùš[H
›Ùš[RQ
NÈ]ÈÛİ\˜Ù\È\™HXœÙ[œ›ÛH\È˜XÚİ\˜]\ˆ[ˆ™XÛÜ™Y\È[\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBƒBˆ]ÛXZ[“˜[YHH›Ùš[RQOH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQBˆÈ
[™K›XZ[‹˜[™RY[YšY\ˆÏÈ˜\‘XÛ\ÙHŠCBˆˆ›Ùš[TÙ][™ÜÔİÜ™KœİZ]S˜[YJ›Üˆ›Ùš[RQ
CBˆ]ÛXZ[ˆH\Ù\‘Y˜][Ëœİ[™\™œ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆÛXZ[“˜[YJHÏÈÎ—CBˆ˜\ˆÙ\šXÙ\ÔÙ][™ÜÎˆÔİš[™Îˆ]WHHÎ—CBˆ›Üˆ
Ù^KÊH[ˆÛXZ[ˆÚ\™HXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœÙ\šXÙ\ÃBˆ	‰ˆP˜XÚİ\]Kš\Õ\YÜ“YØXŞT™XY\”Ûİ\˜ÙTÙ][™ÊÙ^JCBˆ	‰ˆP˜XÚİ\]K˜ÛİY[œØY™TÙ\šXÙ\ÔÙ][™ÜÒÙ^\Ë˜ÛÛZ[œÊÙ^JHÃBˆİX\™]˜[YHHİÜ™K›Øš™Xİ
›Ü’Ù^NˆÙ^JKBˆ]]HHOÈ›Ü\S\İÙ\šX[^˜][Û‹™]JBˆœ›ÛT›Ü\S\İˆ˜[YKBˆ›Ü›X]ˆ˜š[˜\KBˆÜ[ÛœÎˆBˆ
K]K˜Ûİ[HX^[][T›Ùš[TÙ][™Õ˜[YP]\È[ÙHÃBˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÈHÎ—CBˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YH˜[ÙCBˆ™]\›ƒBˆCBˆÙ\šXÙ\ÔÙ][™ÜÖÚÙ^WHH]CBˆCBˆYˆ]ØY™TÙ][™ÜÈH˜XÚİ\]KœÙ\šXÙ\ÔÙ][™ÜÑ›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆÙ\šXÙ\ÔÙ][™ÜÃBˆ
HÃBˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÈHØY™TÙ][™ÜÃBˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YHYCBˆCBƒBˆYˆ[˜ÛYPÛİYÛİ\˜ÙSY]Y]KBˆ]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÓ]š[ÔYÚ[œÈÃBˆ]]š[ÔİÜ™HH]š[ÔYÚ[”İÜ™JY˜][ÎˆİÜ™JCBˆ]İ]HH]š[ÔİÜ™K›ØY

CBˆYˆ[]š[ÔİÜ™Kœİ]UÜš]\Ôİ\Ü[™YÃBˆÛ˜\Úİ›]š[ÔYÚ[œÈHİ]CBˆCBˆH[ÙHYˆ]]HHİÜ™K™]J›Ü’Ù^Nˆ›]š[ÔYÚ[œÔİ]KŒˆŠKBˆ]İ]HHOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJBˆ]š[ÔİÜ™YYÚ[œÔİ]KœÙ[‹Bˆœ›ÛNˆ]CBˆ
HÃBˆÛ˜\Úİ›]š[ÔYÚ[œÈHİ]CBˆCBˆCBƒBˆš]˜]Hİ]XÈ]]šXÙSØØ[›Ùš[TÙ][™ÒÙ^\ÎˆÙ]İš[™ÏˆHÃBˆœÙX\˜Ú\İÜH‹Bˆ™XÛ\ÙTÙ\šXÙ\ÔÙ][™ÜÔÙYYYŒH‹Bˆ˜\X\˜[˜ÙSZYÜ˜]YŒH‹Bˆ™^\š[Y[[T”™[ØY\ÚYØXÚRÙ^\ÓZYÜ˜]Y‹BˆœÛİ\˜ÙRX[™XÛÜ™ÕŒH‹BˆœÛİ\˜ÙRX[\İZ[PÚXÚÕ[Y\İ[\‹Bˆ˜XÚÙ\”[™[™ĞÜ™Y[X[[][ÛœËŒH‹Bˆ˜XÚÙ\”[™[™Ñ\ØØ\™Y›Ùš[PÛX[\ŒH‹Bˆ˜Zİ\İÜUÜš]T™XÙZ\ËŒH‹Bˆ›ØØ[›İYšXØ][Û‘]\™SY]Y]T™Yœ™\Ú]\È‹Bˆ”™XY\‹\ØØ[S[Ù[˜[YHƒBˆCBƒBˆš]˜]Hİ]XÈ]]šXÙSØØ[›Ùš[TÙ][™Ô™Yš^\ÈHÃBˆ›Xœ˜\PÛÛXİ[ÛœÈ‹Bˆ™[˜X›YØ][ÙÜÈ‹Bˆ›X[™ØSXœ˜\PÛÛXİ[ÛœÈ‹Bˆ›X[™ØT™XY[™Ô›ÙÜ™\ÜÈ‹BˆšØ[™[“X[™ØPØ][ÙÜÈ‹BˆšØ[™[İ\İÛPØ][ÙÜÈ‹BˆšØ[™[”™XY\“YØXŞU[˜]˜Z[X›UŒH‹Bˆœ™XY\‘^[œÚ[ÛœË›YØXŞT™XÛÛ›™XİYÙ\ˆ‹Bˆ›YYXTİ]PÛİYÚ]İ\Ü[™Y‹Bˆ™^\š[Y[[ÛİYŞ[˜È‹Bˆ™^\š[Y[[PÛİYŞ[˜È‹Bˆ™^\š[Y[[ÛÛÙÛQš]™TŞ[˜È‹Bˆ™^\š[Y[[Û™Qš]™TŞ[˜ÈƒBˆCBƒBˆİ]XÈ]X^[][T›Ùš[TÙ][™Õ˜[YP]\ÈHLLˆ
ˆWÌBˆİ]XÈ]X^[][T›Ùš[TÙ][™ÒÙ^\ÈHWÌBƒBˆİ]XÈ[˜ÈØ\œšY\Ô›Ùš[TØÛÜYÙ][™ÊÈÙ^Nˆİš[™ÊHOˆ›ÛÛÃBˆ\ÑXÛ\ÙTÙ][™ÒÙ^JÙ^JCBˆ	‰ˆXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœ›Ùš[CBˆ	‰ˆY]šXÙSØØ[›Ùš[TÙ][™ÒÙ^\Ë˜ÛÛZ[œÊÙ^JCBˆ	‰ˆY]šXÙSØØ[›Ùš[TÙ][™Ô™Yš^\Ë˜ÛÛZ[œÊÚ\™NˆÙ^Kš\Ô™Yš^
CBˆCBƒBˆİ]XÈ[˜È˜[Y]Y˜XÚİ\Ù][™Õ˜[YJœ›ÛH]Nˆ]K›Ü’Ù^HÙ^Nˆİš[™ÊHOˆ[OÈÃBˆİX\™]K˜Ûİ[HX^[][T›Ùš[TÙ][™Õ˜[YP]\È[ÙHÈ™]\›ˆš[CBˆYˆ]ØÛÜHHYYXTİ]TÙ][™Ô™YÚ\İKœØÛÜJ›ÜˆÙ^JHÃBˆİX\™ØÛÜK˜\Y\ÕĞİ\œ™[]›Ü›H[ÙHÈ™]\›ˆš[CBˆ™]\›ˆYYXTİ]TÙ][™Õ˜[YU˜[Y]Ü‹˜[Y]Y˜[YJœ›ÛNˆ]K›Ü’Ù^NˆÙ^JCBˆCBˆ™]\›ˆOÈ›Ü\S\İÙ\šX[^˜][Û‹œ›Ü\S\İ
Bˆœ›ÛNˆ]KBˆÜ[ÛœÎˆ×KBˆ›Ü›X]ˆš[Bˆ
CBˆCBƒBˆİ]XÈ[˜ÈÙ\šXÙ\ÔÙ][™Ô\XÚ\]\Ò[”š]˜]PÛİY
ÈÙ^Nˆİš[™ÊHOˆ›ÛÛÃBˆXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœÙ\šXÙ\ÃBˆ	‰ˆP˜XÚİ\]K˜ÛİY[œØY™TÙ\šXÙ\ÔÙ][™ÜÒÙ^\Ë˜ÛÛZ[œÊÙ^JCBˆ	‰ˆP˜XÚİ\]Kš\Õ\YÜ“YØXŞT™XY\”Ûİ\˜ÙTÙ][™ÊÙ^JCBˆCBƒBˆİ]XÈ[˜ÈZ\ÜÚ[™Ğ]]Üš]]]™TÙ\šXÙ\ÔÙ][™ÒÙ^\ÊBˆİ\œ™[ˆÙ]İš[™Ï‹Bˆ[˜ÛÛZ[™ÎˆÙ]İš[™Ï‹BˆØ\\™YÛÛ\][Nˆ›ÛÛBˆ
HOˆÔİš[™×HÃBˆİX\™Ø\\™YÛÛ\][H[ÙHÈ™]\›ˆ×HCBˆ™]\›ˆİ\œ™[™š[\ˆÃBˆÙ\šXÙ\ÔÙ][™Ô\XÚ\]\Ò[”š]˜]PÛİY
	
CBˆ	‰ˆZ[˜ÛÛZ[™Ë˜ÛÛZ[œÊ	
CBˆKœÛÜY

CBˆCBƒBˆš]˜]Hİ]XÈ[˜È™\İÜ™TÙ\šXÙ\ÔÙ][™ÜÊBˆÈÙ][™ÜÎˆÔİš[™Îˆ]WKBˆØ\\™YÛÛ\][Nˆ›ÛÛBˆÈİÜ™Nˆ\Ù\‘Y˜][ËBˆ™\Ù\š[™È]šXÙSØØ[Ûİ\˜ÙRQÎˆÙ]İš[™ÏƒBˆ
HÃBˆ]Ù^\ÈHÜ™\™Y˜]ÔÙ\šXÙ\ÔÙ][™ÒÙ^\ÊÙ][™ÜÊCBˆ][˜ÛÛZ[™ÒÙ^\ÈHÙ]
Ù^\ÊCBˆ]Z\ÜÚ[™ÒÙ^\ÈHZ\ÜÚ[™Ğ]]Üš]]]™TÙ\šXÙ\ÔÙ][™ÒÙ^\ÊBˆİ\œ™[ˆÙ]
İÜ™K™Xİ[Û˜\T™\™\Ù[][ÛŠ
KšÙ^\ÊKBˆ[˜ÛÛZ[™Îˆ[˜ÛÛZ[™ÒÙ^\ËBˆØ\\™YÛÛ\][NˆØ\\™YÛÛ\][CBˆ
CBˆ›ÜˆÙ^H[ˆZ\ÜÚ[™ÒÙ^\ÈÃBˆ]™\Ù]˜[YHH^\š[Y[[ÛİYØØ[Ûİ\˜ÙTÙ[Xİ[Û”ÛXŞKœ™\İÜ™Y˜[YJBˆÔİš[™×J
KBˆ›Ü’Ù^NˆÙ^KBˆİ\œ™[İÜ™NˆİÜ™KBˆ™\Ù\š[™Îˆ]šXÙSØØ[Ûİ\˜ÙRQÃBˆ
CBˆYˆ]™]Z[™YH™\Ù]˜[YH\ÏÈÔİš[™×K\™]Z[™Yš\Ñ[\HÃBˆİÜ™KœÙ]
™]Z[™Y›Ü’Ù^NˆÙ^JCBˆH[ÙHÃBˆİÜ™Kœ™[[İ™SØš™Xİ
›Ü’Ù^NˆÙ^JCBˆCBˆCBˆ›ÜˆÙ^H[ˆÙ^\Ëœ™Yš^
X^[][T›Ùš[TÙ][™ÒÙ^\ÊHÃBˆİX\™]]HHÙ][™ÜÖÚÙ^WKBˆ]XÛÙY˜[YHH˜[Y]Y˜XÚİ\Ù][™Õ˜[YJBˆœ›ÛNˆ]KBˆ›Ü’Ù^NˆÙ^CBˆ
H[ÙHÈÛÛ[YHCBˆ]˜[YHH^\š[Y[[ÛİYØØ[Ûİ\˜ÙTÙ[Xİ[Û”ÛXŞKœ™\İÜ™Y˜[YJBˆXÛÙY˜[YKBˆ›Ü’Ù^NˆÙ^KBˆİ\œ™[İÜ™NˆİÜ™KBˆ™\Ù\š[™Îˆ]šXÙSØØ[Ûİ\˜ÙRQÃBˆ
CBˆİÜ™KœÙ]
˜[YK›Ü’Ù^NˆÙ^JCBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈÜ™\™Y˜]ÔÙ\šXÙ\ÔÙ][™ÒÙ^\ÊBˆÈÙ][™ÜÎˆÔİš[™Îˆ]WCBˆ
HOˆÔİš[™×HÃBˆÙ][™ÜËšÙ^\Ë™š[\ˆÃBˆÙ\šXÙ\ÔÙ][™Ô\XÚ\]\Ò[”š]˜]PÛİY
	
CBˆKœÛÜYÈËšÈ[ƒBˆ]Ò\Ô™YÚ\İ\™YHYYXTİ]TÙ][™Ô™YÚ\İKœØÛÜJ›ÜˆÊHOHš[Bˆ]šÒ\Ô™YÚ\İ\™YHYYXTİ]TÙ][™Ô™YÚ\İKœØÛÜJ›ÜˆšÊHOHš[BˆYˆÒ\Ô™YÚ\İ\™YOHšÒ\Ô™YÚ\İ\™YÈ™]\›ˆÒ\Ô™YÚ\İ\™YCBˆ™]\›ˆÈšÃBˆCBˆCBƒBˆš]˜]Hİ]XÈ[˜È\ÑXÛ\ÙTÙ][™ÒÙ^JÈÙ^Nˆİš[™ÊHOˆ›ÛÛÃBˆYˆÙ^Kš\Ô™Yš^
”™XY\‹ˆŠHÈ™]\›ˆYHCBˆİX\™]š\œİHÙ^K™š\œİš\œİš\ĞTĞÒRKš\œİš\ÓİÙ\˜Ø\ÙH[ÙHÈ™]\›ˆ˜[ÙHCBˆ™]\›ˆZÙ^Kš\Ô™Yš^
˜ÛÛKˆŠCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ\\™T›Ùš[TØÛÜYÙ][™ÜÊ›Ü”›Ùš[H›Ùš[RQˆURQ
HOˆÔİš[™Îˆ]WHÃBˆ]İÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™YœİÜ™J›Üˆ›Ùš[RQ
CBˆ]ÛXZ[“˜[YHH›Ùš[RQOH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQBˆÈ
[™K›XZ[‹˜[™RY[YšY\ˆÏÈ˜\‘XÛ\ÙHŠCBˆˆ›Ùš[TÙ][™ÜÔİÜ™KœİZ]S˜[YJ›Üˆ›Ùš[RQ
CBˆ]ÛXZ[ˆH\Ù\‘Y˜][Ëœİ[™\™œ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆÛXZ[“˜[YJHÏÈÎ—CBƒBˆ˜\ˆÙY[ˆHÙ]
YYXTİ]TÙ][™Ô™YÚ\İK˜[Ù^\Ë™š[\ŠØ\œšY\Ô›Ùš[TØÛÜYÙ][™ÊJCBˆ˜\ˆÙ^\ÈHÙY[‹œÛÜY

CBˆÙ^\Ë˜\[™
ÛÛ[ÓÙˆÛXZ[‹šÙ^\Ë™š[\ˆÃBˆØ\œšY\Ô›Ùš[TØÛÜYÙ][™Ê	
H	‰ˆÙY[‹š[œÙ\
	
Kš[œÙ\YBˆKœÛÜY

JCBƒBˆ˜\ˆ™\İ[ˆÔİš[™Îˆ]WHHÎ—CBˆ˜\ˆÚÚ\Yİ™\œÚ^™YÙ^\ÈHBˆ›ÜˆÙ^H[ˆÙ^\ÈÃBˆİX\™™\İ[˜Ûİ[X^[][T›Ùš[TÙ][™ÒÙ^\È[ÙHÈœ™XZÈCBˆİX\™]˜[YHHİÜ™K›Øš™Xİ
›Ü’Ù^NˆÙ^JKBˆ›Ü\S\İÙ\šX[^˜][Û‹œ›Ü\S\İ
˜[YK\Õ˜[Y›Üˆ˜š[˜\JKBˆ]]HHOÈ›Ü\S\İÙ\šX[^˜][Û‹™]JBˆœ›ÛT›Ü\S\İˆ˜[YKBˆ›Ü›X]ˆ˜š[˜\KBˆÜ[ÛœÎˆBˆ
H[ÙHÃBˆÛÛ[YCBˆCBˆİX\™]K˜Ûİ[HX^[][T›Ùš[TÙ][™Õ˜[YP]\È[ÙHÃBˆÚÚ\Yİ™\œÚ^™YÙ^\È
ÏHCBˆÛÛ[YCBˆCBˆ™\İ[ÚÙ^WHH]CBˆCBˆYˆÚÚ\Yİ™\œÚ^™YÙ^\ÈˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÚÚ\Y
ÚÚ\Yİ™\œÚ^™YÙ^\ÊHİ™\œÚ^™Y›Ùš[HÙ][™ÊÊH›Üˆ›Ùš[H
›Ùš[RQ
H‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆCBˆ™]\›ˆ™\İ[BˆCBƒBˆš]˜]H[˜È\ÔÚŞTİ™X[P˜XÚİ\ÛXZ[”™XYJ
HOˆ›ÛÛÃBˆÚŞTİ™X[P˜XÚİ\ÛXZ[”™XY[™\ÜÊ
HOHœ™XYCBˆCBƒBˆš]˜]H[˜ÈÚŞTİ™X[P˜XÚİ\ÛXZ[”™XY[™\ÜÊ
HOˆ^\š[Y[[ÛİY˜XÚİ\ÛXZ[”™XY[™\ÜÈÃBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆ˜\ˆ™XY[™\ÜÈH^\š[Y[[ÛİY˜XÚİ\ÛXZ[”™XY[™\ÜË›ØY[™ÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ™XY[™\ÜÈHXZ[XİÜ‹˜\Üİ[YR\ÛÛ]YÃBˆ]X[˜YÙ\ˆHÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™YBˆYˆX[˜YÙ\‹š\ÓØYYÈ™]\›ˆœ™XYHCBˆ™]\›ˆX[˜YÙ\‹›\İ\œ›Ü“Y\ÜØYÙHOHš[È›ØY[™Èˆ[˜]˜Z[X›CBˆCBˆCBˆ™]\›ˆ™XY[™\ÜÃBˆÙ[ÙCBˆ™]\›ˆœ™XYCBˆÙ[™YƒBˆCBƒBˆ[˜È™\İÜ™SX[X[˜XÚİ\
ˆœ›ÛH\›ˆT“ˆØÛÜNˆX[X[˜XÚİ\™\İÜ™TØÛÜBˆ
H\Ş[˜ÈOˆ›ÛÛÂˆ™XÛÜ™X[X[™\İÜ™T™\İ[
˜Z[\™T™X\ÛÛˆš[
Bˆ]™Y›YÚˆX[X[™\İÜ™T™Y›YÚˆÈÂˆ™Y›YÚHHX[X[™\İÜ™T™Y›YÚ
œ›ÛNˆ\›
BˆHØ]ÚÂˆ]Y\ÜØYÙHH
\œ›Üˆ\ÏÈØØ[^™Y\œ›ÜŠOË™\œ›Ü‘\ØÜš\[Û‚ˆÏÈ\œ›Ü‹›ØØ[^™Y\ØÜš\[Û‚ˆ™XÛÜ™X[X[™\İÜ™T™\İ[
˜Z[\™T™X\ÛÛˆY\ÜØYÙJBˆÙÙÙ\‹œÚ\™Y›ÙÊ˜XÚİ\™\İÜ™H˜[Y][Ûˆ˜Z[Yˆ
Y\ÜØYÙJH‹\Nˆ‘\œ›ÜˆŠBˆ™]\›ˆ˜[ÙBˆBˆÚYˆÜÊSÔÊBˆİX\™]Ş[˜ÔÙ\ÜÚ[ÛˆH]ØZ]XZ[XİÜ‹œ[Š›ÙNˆÃBˆ^\š[Y[[ÛİYŞ[˜ÓX[˜YÙ\‹œÚ\™Y˜™YÚ[“X[X[™\İÜ™JBˆÙY\ĞÚ[™Ù\ÓÛ•\Ñ]šXÙNˆØÛÜKšÙY\ĞÚ[™Ù\ÓÛ•\Ñ]šXÙCBˆ
CBˆJH[ÙHÂˆÙÙÙ\‹œÚ\™Y›ÙÊˆ˜XÚİ\™\İÜ™HØZ]Y™XØ]\ÙHHÛİYÜ\˜][Ûˆ\Èİ[Xİ]™H‹ˆ\NˆÛİYŞ[˜È‚ˆ
Bˆ™XÛÜ™X[X[™\İÜ™T™\İ[
ˆ˜Z[\™T™X\ÛÛˆHÛİYŞ[˜ÈÜˆ™\İÜ™H\Èİ[[›š[™ËˆØZ]›Üˆ]Èš[š\Ú[ˆ[\ÜH˜XÚİ\YØZ[‹ˆ‚ˆ
Bˆ™]\›ˆ˜[ÙBˆBƒBˆ]İXØÙYYYˆ›ÛÛBˆYˆØ]˜Z[X›JSÔÈMËŒ
ŠHÃBˆİXØÙYYYH]ØZ]YYXTİ]TŞ[˜ÓX[˜YÙ\‹œÚ\™YBˆœ\™›Ü›P]]Üš]]]™TÛ˜\Úİ™\İÜ™HÃBˆ]ØZ]Ù[‹œ™\İÜ™P˜XÚİ\
œ›ÛNˆ\›
CBˆCBˆH[ÙHÃBˆİXØÙYYYH]ØZ]™\İÜ™P˜XÚİ\
œ›ÛNˆ\›
CBˆCBˆ]™\]Z\™\Ô™[][˜ÚH]ØZ]XZ[XİÜ‹œ[ˆÂˆ^\š[Y[[ÛİYŞ[˜ÓX[˜YÙ\‹œÚ\™Y™š[š\ÚX[X[™\İÜ™JˆŞ[˜ÔÙ\ÜÚ[Û‹ˆİXØÙYYYˆİXØÙYYYˆ
BˆİX\™İXØÙYYYˆ]™Y™\œ™Y›Ùš[RQH™Y›YÚœ™Y™\œ™YXİ]™T›Ùš[RQˆ™Y™\œ™Y›Ùš[RQOH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQ[ÙHÂˆ™]\›ˆ˜[ÙBˆBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™YœİYÙT™\İÜ™Y›Ùš[Q›Ü“™^][˜Ú
ˆ™Y™\œ™Y›Ùš[RQˆ
BˆBˆYˆİXØÙYYYÂˆ™XÛÜ™X[X[™\İÜ™T™\İ[
ˆ˜Z[\™T™X\ÛÛˆš[ˆ[\ÜY™XÛÜ™Ûİ[ˆ™Y›YÚØ]Ú™XÛÜ™Ûİ[ˆ™\]Z\™\Ô™[][˜Úˆ™\]Z\™\Ô™[][˜Úˆ
BˆH[ÙHYˆ\İX[X[™\İÜ™Q˜Z[\™T™X\ÛÛˆOHš[Âˆ™XÛÜ™X[X[™\İÜ™T™\İ[
ˆ˜Z[\™T™X\ÛÛˆ•H˜XÚİ\Ûİ[›İ™H\YYˆ›È™\İÜ™Y]HØ\ÈÙ[XİYÈØZ]›Üˆ[HÛİYÜ\˜][ÛˆÈš[š\Ú[™HYØZ[‹ˆ‚ˆ
BˆBˆ™]\›ˆİXØÙYYYˆÙ[ÙBˆ]İXØÙYYYH]ØZ]™\İÜ™P˜XÚİ\
œ›ÛNˆ\›
BˆYˆİXØÙYYYÂˆ™XÛÜ™X[X[™\İÜ™T™\İ[
ˆ˜Z[\™T™X\ÛÛˆš[ˆ[\ÜY™XÛÜ™Ûİ[ˆ™Y›YÚØ]Ú™XÛÜ™Ûİ[ˆ
BˆBˆ™]\›ˆİXØÙYYYˆÙ[™Y‚ˆB‚ˆš]˜]H[˜ÈX[X[™\İÜ™T™Y›YÚ
œ›ÛH\›ˆT“
H›İÜÈOˆX[X[™\İÜ™T™Y›YÚÂˆ]]HHH›İ[™YØØ[İÜ™T™XY\‹œ™XY
ˆœ›ÛNˆ\›ˆX^[][P]\ÎˆÙ[‹›X^[][SX[X[˜XÚİ\š[P]\Âˆ
BˆİX\™]Øš™XİHH”ÓÓ”Ù\šX[^˜][Û‹šœÛÛ“Øš™Xİ
Ú]ˆ]JH\ÏÈÔİš[™Îˆ[WH[ÙHÂˆ›İÈ˜XÚİ\™\İÜ™Q\œ›Ü‹š[˜[YØİ[Y[ˆB‚ˆ]™\œÚ[ÛˆH
Øš™XİÈ™\œÚ[Ûˆ—H\ÏÈİš[™ÊHÏÈŒKŒ‚ˆİX\™Ù[‹˜ÛÛ\\™TØÚ[XU™\œÚ[ÛŠˆ™\œÚ[Û‹ˆÎˆ˜XÚİ\]K˜İ\œ™[ÛİYØÚ[XU™\œÚ[Û‚ˆ
HOH›Ü™\™Y\ØÙ[™[™È[ÙHÂˆ›İÈ˜XÚİ\™\İÜ™Q\œ›Ü‹[œİ\ÜY™\œÚ[ÛŠ™\œÚ[ÛŠBˆB‚ˆ]Û›İÛ”^[ØYÙ^\ÎˆÙ]İš[™ÏˆHÂˆœ›Ùš[\È‹œ›ÙÜ™\ÜÑ]H‹˜ÛÛXİ[ÛœÈ‹œÙ][™ÜÈ‹œÙ\šXÙ\È‹ˆœİ™[Z[ĞYÛœÈ‹˜Ø][ÙÜÈ‹˜XÚÙ\”İ]H‚ˆBˆİX\™ZÛ›İÛ”^[ØYÙ^\Ëš\Ñ\Ú›Ú[
Ú]ˆÙ]
Øš™XİšÙ^\ÊJH[ÙHÂˆ›İÈ˜XÚİ\™\İÜ™Q\œ›Ü‹›Z\ÜÚ[™Ğ˜XÚİ\^[ØYˆB‚ˆ[˜È›ÙÜ™\ÜĞÛİ[
[ˆ˜[YNˆ[OÊHOˆ[ÂˆİX\™]›ÙÜ™\ÜÈH˜[YH\ÏÈÔİš[™Îˆ[WH[ÙHÈ™]\›ˆBˆ][İšYPÛİ[H
›ÙÜ™\ÜÖÈ›[İšYT›ÙÜ™\ÜÈ—H\ÏÈĞ[WJOË˜Ûİ[ÏÈˆ]\\ÛÙPÛİ[H
›ÙÜ™\ÜÖÈ™\\ÛÙT›ÙÜ™\ÜÈ—H\ÏÈĞ[WJOË˜Ûİ[ÏÈˆ™]\›ˆ[İšYPÛİ[
È\\ÛÙPÛİ[ˆB‚ˆ]›Ùš[\ÈHØš™XİÈœ›Ùš[\È—H\ÏÈÖÔİš[™Îˆ[WWBˆ]›Ùš[T™XÛÜ™Ûİ[H›Ùš[\ÏËœ™YXÙJ[Îˆ
HÈÛİ[›Ùš[H[‚ˆÛİ[
ÏH›ÙÜ™\ÜĞÛİ[
[ˆ›Ùš[VÈœ›ÙÜ™\ÜÑ]H—JBˆHÏÈˆ]Ø]Ú™XÛÜ™Ûİ[H›Ùš[T™XÛÜ™Ûİ[ˆˆÈ›Ùš[T™XÛÜ™Ûİ[ˆˆ›ÙÜ™\ÜĞÛİ[
[ˆØš™XİÈœ›ÙÜ™\ÜÑ]H—JBˆ]™Y™\œ™YXİ]™T›Ùš[RQH
Øš™XİÈ˜Xİ]™T›Ùš[RQ—H\ÏÈİš[™ÊBˆ™›]X\
URQš[š]
]ZYİš[™ÎŠJB‚ˆ™]\›ˆX[X[™\İÜ™T™Y›YÚ
ˆØ]Ú™XÛÜ™Ûİ[ˆØ]Ú™XÛÜ™Ûİ[ˆ™Y™\œ™YXİ]™T›Ùš[RQˆ™Y™\œ™YXİ]™T›Ùš[RQˆ
BˆBƒBˆ[˜È™\İÜ™P˜XÚİ\
Bˆœ›ÛH\›ˆT“Bˆ™\Ù\™\ÔŞ[˜ÙYYYXTİ]Nˆ›ÛÛH˜[ÙCBˆ
H\Ş[˜ÈOˆ›ÛÛÃBˆÈÃBˆ]œÛÛ‘]HHH›İ[™YØØ[İÜ™T™XY\‹œ™XY
Bˆœ›ÛNˆ\›BˆX^[][P]\ÎˆÙ[‹›X^[][SX[X[˜XÚİ\š[P]\ÃBˆ
CBˆ]XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆXÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBƒBˆ˜\ˆ˜XÚİ\]Nˆ˜XÚİ\]CBƒBˆÈÃBˆ˜XÚİ\]HHHXÛÙ\‹™XÛÙJ˜XÚİ\]KœÙ[‹œ›ÛNˆœÛÛ‘]JCBˆ˜XÚİ\]HHZYÜ˜][™Ó]š[ÔÚ\™Y^[ØYÑ›Ü”™\İÜ™J˜XÚİ\]JCBˆÙÙÙ\‹œÚ\™Y›ÙÊ˜XÚİ\XÛÙYİXØÙ\ÜÙ[H‹\Nˆ’[™›ÈŠCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ”İ[™\™XÛÙH˜Z[Y][\[™È[šY[™\İÜ™Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\Nˆ’[™›ÈŠCBƒBˆİX\™]XÛÙY˜XÚİ\]HHS[šY[XÛÙJœ›ÛNˆœÛÛ‘]JH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ“[šY[XÛÙH[ÛÈ˜Z[Y‹\Nˆ‘\œ›ÜˆŠCBˆ™]\›ˆ˜[ÙCBˆCBˆ]˜XÚİ\]HHZYÜ˜][™Ó]š[ÔÚ\™Y^[ØYÑ›Ü”™\İÜ™JXÛÙY˜XÚİ\]JCBƒBˆÙÙÙ\‹œÚ\™Y›ÙÊ“[šY[XÛÙHİXØÙYYYÚ]\X[]H‹\Nˆ’[™›ÈŠCBˆ][[™YØÛÜHHXİ]™T›Ùš[TØÛÜUÚÙ[Š
CBˆ]™\İÜ™Tİ\HH]ØZ]™YÚ[”Ú\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆ›Üˆ˜XÚİ\]KBˆ^XİYØÛÜNˆ[[™YØÛÜCBˆ
CBˆ]Ú\™TÙ\šXÙ\Õ˜[œØXİ[ÛˆH™\İÜ™Tİ\˜[œØXİ[ÛƒBˆ]™\İÜ™TØÛÜHH™\İÜ™Tİ\œØÛÜCBƒBˆ]İÛœÕÜ]™[Ûİ\˜Ù\ÈH\Y\ÕÜ]™[Ûİ\˜ÙQ]JBˆ˜XÚİ\]KBˆXİ]™T›Ùš[RQˆ™\İÜ™TØÛÜKœ›Ùš[RQBˆ
CBˆİX\™]ØZ]™\İÜ™TÚŞTİ™X[TÛ˜\Úİ[™ØZ]Y”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈ˜XÚİ\]KœÚŞTİ™X[Hˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]ØZ]™\İÜ™S]š[ÔÛ˜\ÚİY”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈ˜XÚİ\]K›]š[ÔYÚ[œÈˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]Üİ\HH]ØZ]\P˜XÚİ\]RY”ØÛÜR\Ğİ\œ™[
Bˆ˜XÚİ\]KBˆ™\Ù\š[™ÓYØXŞPÛİYYYXTİ]Nˆ™\Ù\™\ÔŞ[˜ÙYYYXTİ]KBˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆ]Üİ\TØÛÜHHÜİ\KœØÛÜCBˆ]ØZ]ÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™Y˜Ø\\™TÛİ\˜ÙQY˜][Ôİ]JBˆ^XİYØÛÜQÙ[™\˜][ÛˆÜİ\TØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
CBˆ]ØZ]™\Z\Xİ]™T›Ùš[TÚŞTİ™X[Tİ]RY“™YYY
Bˆ˜XÚİ\]KBˆ^XİYØÛÜNˆÜİ\TØÛÜCBˆ
CBˆİX\™]ØZ]™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆÜİ\TØÛÜKBˆÛ\˜]\Ò[™\™XY\”[[YNˆYCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆÛÛ\]TÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆYCBˆCBƒBˆ][[™YØÛÜHHXİ]™T›Ùš[TØÛÜUÚÙ[Š
CBˆ]™\İÜ™Tİ\HH]ØZ]™YÚ[”Ú\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆ›Üˆ˜XÚİ\]KBˆ^XİYØÛÜNˆ[[™YØÛÜCBˆ
CBˆ]Ú\™TÙ\šXÙ\Õ˜[œØXİ[ÛˆH™\İÜ™Tİ\˜[œØXİ[ÛƒBˆ]™\İÜ™TØÛÜHH™\İÜ™Tİ\œØÛÜCBˆ]İÛœÕÜ]™[Ûİ\˜Ù\ÈH\Y\ÕÜ]™[Ûİ\˜ÙQ]JBˆ˜XÚİ\]KBˆXİ]™T›Ùš[RQˆ™\İÜ™TØÛÜKœ›Ùš[RQBˆ
CBˆİX\™]ØZ]™\İÜ™TÚŞTİ™X[TÛ˜\Úİ[™ØZ]Y”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈ˜XÚİ\]KœÚŞTİ™X[Hˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]ØZ]™\İÜ™S]š[ÔÛ˜\ÚİY”İ\ÜY
BˆİÛœÕÜ]™[Ûİ\˜Ù\ÈÈ˜XÚİ\]K›]š[ÔYÚ[œÈˆš[Bˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]Üİ\HH]ØZ]\P˜XÚİ\]RY”ØÛÜR\Ğİ\œ™[
Bˆ˜XÚİ\]KBˆ™\Ù\š[™ÓYØXŞPÛİYYYXTİ]Nˆ™\Ù\™\ÔŞ[˜ÙYYYXTİ]KBˆ^XİYØÛÜNˆ™\İÜ™TØÛÜCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆ]Üİ\TØÛÜHHÜİ\KœØÛÜCBˆ]ØZ]ÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™Y˜Ø\\™TÛİ\˜ÙQY˜][Ôİ]JBˆ^XİYØÛÜQÙ[™\˜][ÛˆÜİ\TØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
CBˆ]ØZ]™\Z\Xİ]™T›Ùš[TÚŞTİ™X[Tİ]RY“™YYY
Bˆ˜XÚİ\]KBˆ^XİYØÛÜNˆÜİ\TØÛÜCBˆ
CBˆİX\™]ØZ]™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆÜİ\TØÛÜKBˆÛ\˜]\Ò[™\™XY\”[[YNˆYCBˆ
H[ÙHÃBˆ]ØZ]™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆ˜[ÙCBˆCBˆÛÛ\]TÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠÚ\™TÙ\šXÙ\Õ˜[œØXİ[ÛŠCBˆ™]\›ˆYCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ‘˜Z[YÈ™\İÜ™H˜XÚİ\ˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹\Nˆ‘\œ›ÜˆŠCBˆ™]\›ˆ˜[ÙCBˆCBˆCBƒBˆš]˜]H[˜ÈS[šY[XÛÙJœ›ÛHœÛÛ‘]Nˆ]JHOˆ˜XÚİ\]OÈÃBˆİX\™]œÛÛˆHOÈ”ÓÓ”Ù\šX[^˜][Û‹šœÛÛ“Øš™Xİ
Ú]ˆœÛÛ‘]JH\ÏÈÔİš[™Îˆ[WH[ÙHÃBˆ™]\›ˆš[BˆCBƒBˆ][šY[XÛÙ\ˆH”ÓÓ‘XÛÙ\Š
CBˆ[šY[XÛÙ\‹™]QXÛÙ[™Ôİ˜]YŞHHš\ÛÎŒCBƒBˆ]Ü™X]Y]Nˆ]CBˆYˆ]]Tİš[™ÈHœÛÛ–È˜Ü™X]Y]H—H\ÏÈİš[™ÈÃBˆ]›Ü›X]\ˆHTÓÎŒQ]Q›Ü›X]\Š
CBˆÜ™X]Y]HH›Ü›X]\‹™]Jœ›ÛNˆ]Tİš[™ÊHÏÈ]J
CBˆH[ÙHÃBˆÜ™X]Y]HH]J
CBˆCBƒBˆ]™\œÚ[ÛˆHœÛÛ–È™\œÚ[Ûˆ—H\ÏÈİš[™ÈÏÈŒKŒƒBˆ]XØÙ[ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È˜XØÙ[ÛÛÜˆ—JCBˆ]Ù][™ÜÑÜ˜YY[ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–ÈœÙ][™ÜÑÜ˜YY[ÛÛÜˆ—JCBˆ]™XY\XØÙ[ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–Èœ™XY\XØÙ[ÛÛÜˆ—JCBˆ]™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–Èœ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆ—JCBˆ]Y“[™İXYÙHHœÛÛ–ÈY“[™İXYÙH—H\ÏÈİš[™ÈÏÈ™[‹UTÈƒBˆ]Ù[XİY\X\˜[˜ÙHH˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJœÛÛ–ÈœÙ[XİY\X\˜[˜ÙH—H\ÏÈİš[™ÊCBˆ]™XY\”Ù[XİY\X\˜[˜ÙHH˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJœÛÛ–Èœ™XY\”Ù[XİY\X\˜[˜ÙH—H\ÏÈİš[™ÈÏÈÙ[XİY\X\˜[˜ÙJCBˆ]™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YHœÛÛ–Èœ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ][˜X›TİX]\ĞQY˜][HœÛÛ–È™[˜X›TİX]\ĞQY˜][—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Y˜][İX]S[™İXYÙHHœÛÛ–È™Y˜][İX]S[™İXYÙH—H\ÏÈİš[™ÈÏÈ™[™ÈƒBˆ]^Y\”İX]P\X\˜[˜ÙQ[˜X›YHœÛÛ–Èœ^Y\”İX]P\X\˜[˜ÙQ[˜X›Y—H\ÏÈ›ÛÛBˆÏÈœÛÛ–È™[˜X›U“ÔİX]QY]Y[H—H\ÏÈ›ÛÛBˆÏÈYCBˆ]™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙHHœÛÛ–Èœ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙH—H\ÏÈİš[™ÈÏÈ™[™ÈƒBˆ]™Y™\œ™Y[š[YP]Y[Ó[™İXYÙHHœÛÛ–Èœ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙH—H\ÏÈİš[™ÈÏÈšœˆƒBˆ][\^Y\ˆHÙ][™ÜË››Ü›X[^™Y[\^Y\ŠœÛÛ–Èš[\^Y\ˆ—H\ÏÈİš[™ÈÏÈœÛÛ–Èœ^Y\ÚÚXÙH—H\ÏÈİš[™ÊCBˆ]ÚİÔØÚY[UXˆHœÛÛ–ÈœÚİÔØÚY[UXˆ—H\ÏÈ›ÛÛÏÈYCBˆ]ÚİÓØØ[ØÚY[U[YHHœÛÛ–ÈœÚİÓØØ[ØÚY[U[YH—H\ÏÈ›ÛÛÏÈYCBˆ]Y˜][ØÚY[S[ÙHHØÚY[S[ÙKœØ[š]^™Y˜]Õ˜[YJœÛÛ–È™Y˜][ØÚY[S[ÙH—H\ÏÈİš[™ÊCBˆ]ØÚY[UÚ[™İÑ^\ÈHØÚY[UÚ[™İËœØ[š]^™Y^\ÊœÛÛ–ÈœØÚY[UÚ[™İÑ^\È—H\ÏÈ[
CBˆ]ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”İXœØÜš\[ÛœÊBˆœÛÛ–È›ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈ—H\ÏÈİš[™ÃBˆ
CBˆ]ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÊBˆœÛÛ–È›ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈ—H\ÏÈİš[™ÃBˆ
CBˆ]ØØ[›İYšXØ][Û‘\\ÛÙSXY[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙSXY[YJBˆœÛÛ–È›ØØ[›İYšXØ][Û‘\\ÛÙSXY[YH—H\ÏÈ[Bˆ
CBˆ]ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YJBˆœÛÛ–È›ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YH—H\ÏÈ[Bˆ
CBˆ]ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÈHœÛÛ–È›ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[È—H\ÏÈ›ÛÛBƒBˆ]Y˜][^X˜XÚÔÜYYH˜XÚİ\]KœØ[š]^™YY˜][^X˜XÚÔÜYY
BˆœÛÛ–È™Y˜][^X˜XÚÔÜYY—H\ÏÈİX›CBˆ
CBˆ]ÛÜYY^Y\ˆH˜XÚİ\]KœØ[š]^™YÛÜYY^Y\ŠBˆœÛÛ–ÈšÛÜYY^Y\ˆ—H\ÏÈİX›CBˆ
CBˆ]^\›˜[^Y\ˆHœÛÛ–È™^\›˜[^Y\ˆ—H\ÏÈİš[™ÈÏÈ››Û™HƒBˆ]™Y™\‘İÛ›ØYYYYXHHœÛÛ–Èœ™Y™\‘İÛ›ØYYYYXH—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ][Ø^\Ó[™ØØ\HHœÛÛ–È˜[Ø^\Ó[™ØØ\H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^Y\”^X˜XÚÓØÚÑ[˜X›YHœÛÛ–Èœ^Y\”^X˜XÚÓØÚÑ[˜X›Y—H\ÏÈ›ÛÛÏÈ^Y\”^X˜XÚÓØÚÔÙ][™ÜË™Y˜][[˜X›YBˆ][šTÚÚ\[˜X›YHœÛÛ–È˜[šTÚÚ\[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ][›Ñ‘[˜X›YHœÛÛ–Èš[›Ñ‘[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ][›Ñ\[˜X›YHœÛÛ–Èš[›Ñ\[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ][šTÚÚ\]]ÔÚÚ\HœÛÛ–È˜[šTÚÚ\]]ÔÚÚ\—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]ÚÚ\\Ñ[˜X›YHœÛÛ–ÈœÚÚ\\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]ÚÚ\\Ğ[Ø^\Õš\ÚX›HHœÛÛ–ÈœÚÚ\\Ğ[Ø^\Õš\ÚX›H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]ÚİÓ™^\\ÛÙP]ÛˆHœÛÛ–ÈœÚİÓ™^\\ÛÙP]Ûˆ—H\ÏÈ›ÛÛÏÈYCBˆ]ÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆHœÛÛ–ÈœÚİÑ\\ÛÙPœ›İÜÙ\]Ûˆ—H\ÏÈ›ÛÛÏÈœÛÛ–ÈœÚİÕ“Ñ\\ÛÙPœ›İÜÙ\]Ûˆ—H\ÏÈ›ÛÛÏÈYCBˆ]ÚİÔ^Y\”Ù\šXÙ\Ğ]ÛˆHœÛÛ–ÈœÚİÔ^Y\”Ù\šXÙ\Ğ]Ûˆ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]ÚİÓ™^\\ÛÙTÜİ\]ÛˆHœÛÛ–ÈœÚİÓ™^\\ÛÙTÜİ\]Ûˆ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™^\\ÛÙU™\ÚÛH˜XÚİ\]KœØ[š]^™Y™^\\ÛÙU™\ÚÛ
BˆœÛÛ–È›™^\\ÛÙU™\ÚÛ—H\ÏÈİX›CBˆ
CBˆ]™^\\ÛÙTÚÚ\š[\‘[˜X›YHœÛÛ–È›™^\\ÛÙTÚÚ\š[\‘[˜X›Y—H\ÏÈ›ÛÛÏÈ™^\\ÛÙQš[\”Ù][™ÜË™Y˜][[˜X›YBˆ]^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YHœÛÛ–Èœ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈœÛÛ–È›ĞœšYÚ™\ÜÑÙ\İ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^Y\•›Û[YQÙ\İ\™Q[˜X›YHœÛÛ–Èœ^Y\•›Û[YQÙ\İ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈœÛÛ–È›Õ›Û[YQÙ\İ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YHœÛÛ–Èœ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^Y\Ù[\•\^T]\ÙQ[˜X›YHœÛÛ–Èœ^Y\Ù[\•\^T]\ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^Y\‘İX›U\ÙYZÑ[˜X›YHœÛÛ–Èœ^Y\‘İX›U\ÙYZÑ[˜X›Y—H\ÏÈ›ÛÛÏÈœÛÛ–È›ÑİX›U\ÙYZÑ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^Y\‘İX›U\ÙYZÔÙXÛÛ™ÈH˜XÚİ\]KœØ[š]^™Y^Y\‘İX›U\ÙYZÔÙXÛÛ™ÊBˆœÛÛ–Èœ^Y\‘İX›U\ÙYZÔÙXÛÛ™È—H\ÏÈİX›CBˆÏÈœÛÛ–È›ÑİX›U\ÙYZÔÙXÛÛ™È—H\ÏÈİX›CBˆ
CBˆ]^Y\“Ü[”İX]\Ñ[˜X›YHœÛÛ–Èœ^Y\“Ü[”İX]\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈœÛÛ–È›ÓÜ[”İX]\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YHœÛÛ–Èœ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›Y—H\ÏÈ›ÛÛÏÈœÛÛ–È›ÓÜ[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›YHœÛÛ–Èœ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]\‘›Ü™YÜ›İ[™”Ô˜]ÈH˜XÚİ\]K›Ü[Û˜[[
Bˆœ›ÛNˆœÛÛ–È›\‘›Ü™YÜ›İ[™”È—KBˆY˜][˜[YNˆÌBˆ
CBˆ]\‘›Ü™YÜ›İ[™”ÈH\‘›Ü™YÜ›İ[™”Ô˜]ÈOHŒÈŒˆÌBˆ]\”™[™\˜XÚÙ[™H˜XÚİ\]KœØ[š]^™YT”™[™\˜XÚÙ[™
œÛÛ–È›\”™[™\˜XÚÙ[™—H\ÏÈİš[™ÊCBˆ]\“Y][]X[]T›Ùš[HH˜XÚİ\]KœØ[š]^™YT“Y][]X[]T›Ùš[JœÛÛ–È›\“Y][]X[]T›Ùš[H—H\ÏÈİš[™ÊCBˆ]\•\ØØ[[™Ó[ÙHH˜XÚİ\]KœØ[š]^™YT•\ØØ[[™Ó[ÙJœÛÛ–È›\•\ØØ[[™Ó[ÙH—H\ÏÈİš[™ÊCBˆ]\“™]\˜[\ØØ[\ˆH˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\ŠœÛÛ–È›\“™]\˜[\ØØ[\ˆ—H\ÏÈİš[™ÊCBˆ]\“™]\˜[\ØØ[\•ˆH˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\ŠœÛÛ–È›\“™]\˜[\ØØ[\•ˆ—H\ÏÈİš[™ÊCBˆ]\”^Y\”ÚÚ[ˆH˜XÚİ\]KœØ[š]^™YT”^Y\”ÚÚ[ŠœÛÛ–È›\”^Y\”ÚÚ[ˆ—H\ÏÈİš[™ÊCBˆ]\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È›\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆ—JCBˆ]\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È›\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆ—JCBˆ]\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›YHœÛÛ–È›\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›Y—H\ÏÈ›ÛÛÏÈT”^Y\”ÚÚ[”Ù][™ÜË™Y˜][[š[X][ÛœÑ[˜X›YBˆ]\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›HHœÛÛ–È›\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›H—H\ÏÈ›ÛÛÏÈT”^Y\”ÚÚ[”Ù][™ÜË™Y˜][[ÛÛ›ÛÓÛ›CBˆ]\”Xİ\™R[”Xİ\™Q[˜X›YHœÛÛ–È›\”Xİ\™R[”Xİ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]\\^]Xİ\™R[”Xİ\™Q[˜X›YHœÛÛ–È›\\^]Xİ\™R[”Xİ\™Q[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]\’“[ÙHHT’“[ÙJ˜]Õ˜[YNˆœÛÛ–È›\’“[ÙH—H\ÏÈİš[™ÈÏÈT’“[ÙK™Y˜][[ÙKœ˜]Õ˜[YJOËœ˜]Õ˜[YHÏÈT’“[ÙK™Y˜][[ÙKœ˜]Õ˜[YCBˆ]\”İ\œ›İ[™Ûİ[™[˜X›YHœÛÛ–È›\”İ\œ›İ[™Ûİ[™[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]Ø]ÚÙÙ]\‘[˜X›YHœÛÛ–ÈØ]ÚÙÙ]\‘[˜X›Y—H\ÏÈ›ÛÛÏÈØ]ÚÙÙ]\”Ù][™ÜË™Y˜][[˜X›YBˆ]ÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YHœÛÛ–ÈœÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^\š[Y[[™X]\™\Ñ[˜X›YHœÛÛ–È™^\š[Y[[™X]\™\Ñ[˜X›Y—H\ÏÈ›ÛÛBˆ]^\š[Y[[™X]\™\Ó\İÚ[™ÙY]H˜XÚİ\]KœØ[š]^™Y^\š[Y[[™X]\™\Ó\İÚ[™ÙY]
BˆœÛÛ–È™^\š[Y[[™X]\™\Ó\İÚ[™ÙY]—H\ÏÈİX›CBˆ
CBˆ]^\š[Y[[T”™[ØY[˜X›YHœÛÛ–È™^\š[Y[[T”™[ØY[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›YHœÛÛ–È™^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]^\š[Y[[T”™[ØYÙ[[\‘[˜X›YHœÛÛ–È™^\š[Y[[T”™[ØYÙ[[\‘[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^\š[Y[[T”™[ØYÚYšS[Z]PˆH^\š[Y[[™X]\™Tİ]Kœ™\ÛÛ™YT”™[ØYÚYšS[Z]PŠ˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–È™^\š[Y[[T”™[ØYÚYšS[Z]Pˆ—KY˜][˜[YNˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÚYšQY˜][[Z]PŠJCBˆ]^\š[Y[[T”™[ØYÙ[[\“[Z]PˆH^\š[Y[[™X]\™Tİ]Kœ™\ÛÛ™YT”™[ØYÙ[[\“[Z]PŠ˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–È™^\š[Y[[T”™[ØYÙ[[\“[Z]Pˆ—KY˜][˜[YNˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÙ[[\‘Y˜][[Z]PŠJCBˆ]^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YHHœÛÛ–È™^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YH—H\ÏÈ›ÛÛÏÈYCBˆ]^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜÈHœÛÛ–È™^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜÈ—H\ÏÈ›ÛÛÏÈYCBˆ]^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\ÈHœÛÛ–È™^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^\š[Y[[T”™[ØY]]ĞÛX\ˆHœÛÛ–È™^\š[Y[[T”™[ØY]]ĞÛX\ˆ—H\ÏÈ›ÛÛÏÈYCBˆ]^\š[Y[[PÛİYŞ[˜Ñ[˜X›YHœÛÛ–È™^\š[Y[[PÛİYŞ[˜Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBƒBˆ]İX]Q›Ü™YÜ›İ[™ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–ÈœİX]Q›Ü™YÜ›İ[™ÛÛÜˆ—JCBˆ]İX]Tİ›ÚÙPÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–ÈœİX]Tİ›ÚÙPÛÛÜˆ—JCBˆ]İX]Tİ›ÚÙUÚYH˜XÚİ\]KœØ[š]^™YİX]Tİ›ÚÙUÚY
BˆœÛÛ–ÈœİX]Tİ›ÚÙUÚY—H\ÏÈİX›CBˆ
CBˆ]İX]Q›ÛÚ^™HH˜XÚİ\]KœØ[š]^™YİX]Q›ÛÚ^™JBˆœÛÛ–ÈœİX]Q›ÛÚ^™H—H\ÏÈİX›CBˆ
CBˆ]İX]U™\XØ[Ù™œÙ]H˜XÚİ\]KœØ[š]^™YİX]U™\XØ[Ù™œÙ]
BˆœÛÛ–ÈœİX]U™\XØ[Ù™œÙ]—H\ÏÈİX›CBˆ
CBˆ]İX]\Õš\ÚX›HHœÛÛ–ÈœİX]\Õš\ÚX›H—H\ÏÈ›ÛÛÏÈ˜[ÙCBƒBˆ]ÚİÒØ[™[ˆHœÛÛ–ÈœÚİÒØ[™[ˆ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]YTÜ\ÚØÜ™Y[ˆHœÛÛ–ÈšYTÜ\ÚØÜ™Y[ˆ—H\ÏÈ›ÛÛBˆ][ÙTİÚ]Ú[š[X][Û‘[˜X›YHœÛÛ–È›[ÙTİÚ]Ú[š[X][Û‘[˜X›Y—H\ÏÈ›ÛÛÏÈ[ÙTİÚ]Ú[š[X][Û”Ù][™ÜË™Y˜][[˜X›YBˆ]Ø[™[]]Õ\]S[Ù[\ÈHœÛÛ–ÈšØ[™[]]Õ\]S[Ù[\È—H\ÏÈ›ÛÛÏÈYCBˆ]ÙX\ÛÛ“Y[HHœÛÛ–ÈœÙX\ÛÛ“Y[H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Üš^›Û[\\ÛÙS\İHœÛÛ–ÈšÜš^›Û[\\ÛÙS\İ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]YYXQ]Z[]P\ÛÜšÑ[˜X›YHœÛÛ–È›YYXQ]Z[]P\ÛÜšÑ[˜X›Y—H\ÏÈ›ÛÛÏÈYYXQ]Z[]P\ÛÜšÔÙ][™ÜË™Y˜][[˜X›YBˆ]YYXQ]Z[[\›˜]TÜİ\‘[˜X›YHœÛÛ–È›YYXQ]Z[[\›˜]TÜİ\‘[˜X›Y—H\ÏÈ›ÛÛÏÈYYXQ]Z[[\›˜]TÜİ\”Ù][™ÜË™Y˜][[˜X›YBˆ]YYXQ]Z[Ú[Z[\•]\Ñ[˜X›YHœÛÛ–È›YYXQ]Z[Ú[Z[\•]\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈYYXQ]Z[Ú[Z[\•]\ÔÙ][™ÜË™Y˜][[˜X›YBˆ]\ÙPÛ\ÜÚXÔØÚY[URHHœÛÛ–È\ÙPÛ\ÜÚXÔØÚY[URH—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]\›Ğ˜[›™\Ø][ÙÒYH˜XÚİ\]KœØ[š]^™Y›Û‘[\Tİš[™ÊœÛÛ–Èš\›Ğ˜[›™\Ø][ÙÒY—H\ÏÈİš[™ËY˜][˜[YNˆ™[™[™ÈŠCBˆ]\›Ğ˜[›™\™Z]š[ÜˆH˜XÚİ\]KœØ[š]^™Y\›Ğ˜[›™\™Z]š[ÜŠœÛÛ–Èš\›Ğ˜[›™\™Z]š[Üˆ—H\ÏÈİš[™ÊCBˆ]ÛYPØ][ÙÓ^[İ]İ™\œšY\ÈHœÛÛ–ÈšÛYPØ][ÙÓ^[İ]İ™\œšY\È—H\ÏÈİš[™ÈÏÈˆƒBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YHœÛÛ–ÈšÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›Y—H\ÏÈ›ÛÛBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]HH˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]JœÛÛ–ÈšÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]H—H\ÏÈİš[™ÊCBˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]HH˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]JœÛÛ–ÈšÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]H—H\ÏÈİš[™ÊCBˆ]\\™›Ü›X[˜ÙSİ™\›^Q[˜X›YHœÛÛ–È˜\\™›Ü›X[˜ÙSİ™\›^Q[˜X›Y—H\ÏÈ›ÛÛÏÈ\\™›Ü›X[˜ÙSİ™\›^TÙ][™ÜË™Y˜][[˜X›YBˆ]^\š[Y[[YYXQ\ÚYÛ”™\Ù]H˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXQ\ÚYÛ”™\Ù]
œÛÛ–È™^\š[Y[[YYXQ\ÚYÛ”™\Ù]—H\ÏÈİš[™ÊCBˆ]^\š[Y[[\›Ğ›YY]™[H˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YY]™[
œÛÛ–È™^\š[Y[[\›Ğ›YY]™[—H\ÏÈİš[™ÊCBˆ]^\š[Y[[ÛYPØ\™Ú\HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÛYPØ\™Ú\JœÛÛ–È™^\š[Y[[ÛYPØ\™Ú\H—H\ÏÈİš[™ÊCBˆ]^\š[Y[[][QÜ˜YY[[]HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[][QÜ˜YY[[]JœÛÛ–È™^\š[Y[[][QÜ˜YY[[]H—H\ÏÈİš[™ÊCBˆ]^\š[Y[[\›ÒZYÚØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›ÒZYÚØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[\›ÒZYÚØØ[H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›ÒZYÚØØ[JJCBˆ]^\š[Y[[\›Ğ›YYİ™[™İH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YYİ™[™İ
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[\›Ğ›YYİ™[™İ—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›Ğ›YYİ™[™İ
JCBˆ]^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][\›Ñ˜YQ\İ[˜ÙTØØ[JJCBˆ]^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][ÙXİ[Û”ÜXÚ[™ÔØØ[JJCBˆ]^\š[Y[[Ø\™˜Y]\ÔØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ø\™˜Y]\ÔØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ø\™˜Y]\ÔØØ[H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ø\™˜Y]\ÔØØ[JJCBˆ]^\š[Y[[YYXPØ\™ØØ[HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXPØ\™ØØ[J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[YYXPØ\™ØØ[H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][YYXPØ\™ØØ[JJCBˆ]^\š[Y[[Û\ÜÔİ™[™İH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Û\ÜÔİ™[™İ
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[Û\ÜÔİ™[™İ—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Û\ÜÔİ™[™İ
JCBˆ]^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÈH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÊ˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÈ—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[˜\ÙQ\šÛ™\ÜÊJCBˆ]^\š[Y[[Ü˜YY[XØÙ[[[œÚ]HH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[XØÙ[[[œÚ]J˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[XØÙ[[[œÚ]H—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[XØÙ[[[œÚ]JJCBˆ]^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛˆH˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛŠ˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[ØÜ›Û[İ[Ûˆ—KY˜][˜[YNˆ^\š[Y[[š\İX[[š[™Ë™Y˜][Ü˜YY[ØÜ›Û[İ[ÛŠJCBˆ]^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœÈHœÛÛ–È™^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœÈ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]^\š[Y[[Ü˜YY[ÛÛÜHH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[ÛÛÜH—JCBˆ]^\š[Y[[Ü˜YY[ÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[ÛÛÜˆ—JCBˆ]^\š[Y[[Ü˜YY[ÛÛÜÈH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È™^\š[Y[[Ü˜YY[ÛÛÜÈ—JCBˆ]][ÜÜ\™Tİ[HH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[JœÛÛ–È˜][ÜÜ\™Tİ[H—H\ÏÈİš[™ÊCBˆ]][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJœÛÛ–È˜][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙH—H\ÏÈİš[™ÊCBˆ]][ÜÜ\™TÛÛYÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–È˜][ÜÜ\™TÛÛYÛÛÜˆ—JCBˆ]™XY\][ÜÜ\™Tİ[HH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[JœÛÛ–Èœ™XY\][ÜÜ\™Tİ[H—H\ÏÈİš[™ÈÏÈ][ÜÜ\™Tİ[JCBˆ]™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHH˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJœÛÛ–Èœ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙH—H\ÏÈİš[™ÈÏÈ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJCBˆ]™XY\][ÜÜ\™TÛÛYÛÛÜˆH˜XÚİ\]K˜˜XÚİ\ÛÛÜ‘]Jœ›ÛNˆœÛÛ–Èœ™XY\][ÜÜ\™TÛÛYÛÛÜˆ—JCBˆ]YYXQ]Z[[[Y[Ü™\ˆH˜XÚİ\]KœØ[š]^™YYYXQ]Z[[[Y[Ü™\ŠœÛÛ–È›YYXQ]Z[[[Y[Ü™\ˆ—H\ÏÈİš[™ÊCBˆ]YYXQ]Z[Y[‘[[Y[ÈH˜XÚİ\]KœØ[š]^™YYYXQ]Z[Y[‘[[Y[ÊœÛÛ–È›YYXQ]Z[Y[‘[[Y[È—H\ÏÈİš[™ÊCBˆ]™XY\‘]Z[[[Y[Ü™\ˆH˜XÚİ\]KœØ[š]^™Y™XY\‘]Z[[[Y[Ü™\ŠœÛÛ–Èœ™XY\‘]Z[[[Y[Ü™\ˆ—H\ÏÈİš[™ÊCBˆ]™XY\‘]Z[Y[‘[[Y[ÈH˜XÚİ\]KœØ[š]^™Y™XY\‘]Z[Y[‘[[Y[ÊœÛÛ–Èœ™XY\‘]Z[Y[‘[[Y[È—H\ÏÈİš[™ÊCBˆ]YYXPÛÛ[[œÔÜ˜Z]HœÛÛ–È›YYXPÛÛ[[œÔÜ˜Z]—H\ÏÈ[ÏÈÃBˆ]YYXPÛÛ[[œÓ[™ØØ\HHœÛÛ–È›YYXPÛÛ[[œÓ[™ØØ\H—H\ÏÈ[ÏÈCBƒBˆ]™XY[™Ó[ÙHH˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–Èœ™XY[™Ó[ÙH—KY˜][˜[YNˆŠCBˆ]Ø[™[”™XY\“[ÙHH
œÛÛ–ÈšØ[™[”™XY\“[ÙH—H\ÏÈİš[™ÊK›X\
˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙJCBˆÏÈ˜XÚİ\]KšØ[™[”™XY\“[ÙT˜]Õ˜[YJ›Ü”™XY[™Ó[ÙNˆ™XY[™Ó[ÙJCBˆ]Ø[™[”™XY\“[ÙSİ™\œšY\ÈH˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙSİ™\œšY\ÊœÛÛ–ÈšØ[™[”™XY\“[ÙSİ™\œšY\È—H\ÏÈÔİš[™Îˆİš[™×JCBˆ]™XY\‘İÛœØ[\R[XYÙ\ÈHœÛÛ–Èœ™XY\‘İÛœØ[\R[XYÙ\È—H\ÏÈ›ÛÛÏÈYCBˆ]™XY\Ü›Ü›Ü™\œÈHœÛÛ–Èœ™XY\Ü›Ü›Ü™\œÈ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\‘\ØX›T]ZXÚĞXİ[ÛœÈHœÛÛ–Èœ™XY\‘\ØX›T]ZXÚĞXİ[ÛœÈ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\‘\ØX›QİX›U\HœÛÛ–Èœ™XY\‘\ØX›QİX›U\—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\“]™U^HœÛÛ–Èœ™XY\“]™U^—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\’YP˜\œÓÛ”İÚ\HHœÛÛ–Èœ™XY\’YP˜\œÓÛ”İÚ\H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\˜XÚÙÜ›İ[™ÛÛÜˆH˜XÚİ\]KœØ[š]^™Y™XY\˜XÚÙÜ›İ[™ÛÛÜŠœÛÛ–Èœ™XY\˜XÚÙÜ›İ[™ÛÛÜˆ—H\ÏÈİš[™ÊCBˆ]™XY\“ÜšY[][ÛˆH˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][ÛŠœÛÛ–Èœ™XY\“ÜšY[][Ûˆ—H\ÏÈİš[™ÊCBˆ]™XY\•\›Û™\ÈH˜XÚİ\]KœØ[š]^™Y™XY\•\›Û™\ÊœÛÛ–Èœ™XY\•\›Û™\È—H\ÏÈİš[™ÊCBˆ]™XY\’[™\\›Û™\ÈHœÛÛ–Èœ™XY\’[™\\›Û™\È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\[š[X]TYÙU˜[œÚ][ÛœÈHœÛÛ–Èœ™XY\[š[X]TYÙU˜[œÚ][ÛœÈ—H\ÏÈ›ÛÛÏÈYCBˆ]™XY\•\ØØ[R[XYÙ\ÈHœÛÛ–Èœ™XY\•\ØØ[R[XYÙ\È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\•\ØØ[SX^ZYÚH˜XÚİ\]KœØ[š]^™Y™XY\•\ØØ[SX^ZYÚ
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–Èœ™XY\•\ØØ[SX^ZYÚ—KY˜][˜[YNˆŒ
JCBˆ]™XY\•\ØØ[S[Ù[˜[YHHœÛÛ–Èœ™XY\•\ØØ[S[Ù[˜[YH—H\ÏÈİš[™ÈÏÈ“›Û™HƒBˆ]™XY\”YÙ\ÕÔ™[ØYH˜XÚİ\]KœØ[š]^™Y™XY\”YÙ\ÕÔ™[ØY
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–Èœ™XY\”YÙ\ÕÔ™[ØY—KY˜][˜[YNˆÊJCBˆ]™XY\”YÙYYÙS^[İ]H˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙS^[İ]
œÛÛ–Èœ™XY\”YÙYYÙS^[İ]—H\ÏÈİš[™ÊCBˆ]™XY\”YÙYYÙSÙ™œÙ]HœÛÛ–Èœ™XY\”YÙYYÙSÙ™œÙ]—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ÈH˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ÊœÛÛ–Èœ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\È—H\ÏÈÔİš[™Îˆ›ÛÛJCBˆ]™XY\”Ü]ÚYR[XYÙ\ÈHœÛÛ–Èœ™XY\”Ü]ÚYR[XYÙ\È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\”™]™\œÙTÜ]Ü™\ˆHœÛÛ–Èœ™XY\”™]™\œÙTÜ]Ü™\ˆ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\•™\XØ[[™š[š]TØÜ›ÛHœÛÛ–Èœ™XY\•™\XØ[[™š[š]TØÜ›Û—H\ÏÈ›ÛÛÏÈYCBˆ]™XY\”[\˜›ŞHœÛÛ–Èœ™XY\”[\˜›Ş—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\”[\˜›Ş[[İ[H˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›Ş[[İ[
˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–Èœ™XY\”[\˜›Ş[[İ[—KY˜][˜[YNˆMJJCBˆ]™XY\”[\˜›ŞÜšY[][ÛˆH˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›ŞÜšY[][ÛŠœÛÛ–Èœ™XY\”[\˜›ŞÜšY[][Ûˆ—H\ÏÈİš[™ÊCBˆ]™XY\“ÜšY[][Û“ØÚÑ[˜X›YHœÛÛ–Èœ™XY\“ÜšY[][Û“ØÚÑ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\“ÜšY[][Û“ØÚÓX\ÚÈH˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][Û“ØÚÓX\ÚÊœÛÛ–Èœ™XY\“ÜšY[][Û“ØÚÓX\ÚÈ—H\ÏÈİš[™ÊCBˆ]™XY\”™XY™\ÚÛ\˜Ù[H˜XÚİ\]KœØ[š]^™Y™XY\”™XY™\ÚÛ\˜Ù[
œÛÛ–Èœ™XY\”™XY™\ÚÛ\˜Ù[—H\ÏÈİX›JCBƒBˆ]™XY\‘›ÛÚ^™HH˜XÚİ\]KœØ[š]^™Y™XY\‘›ÛÚ^™JBˆœÛÛ–Èœ™XY\‘›ÛÚ^™H—H\ÏÈİX›CBˆ
CBˆ]™XY\‘›Û˜[Z[HHœÛÛ–Èœ™XY\‘›Û˜[Z[H—H\ÏÈİš[™ÈÏÈ‹X\K\Ş\İ[HƒBˆ]™XY\‘›ÛÙZYÚHœÛÛ–Èœ™XY\‘›ÛÙZYÚ—H\ÏÈİš[™ÈÏÈ››Ü›X[ƒBˆ]™XY\ÛÛÜ”™\Ù]H˜XÚİ\]KœØ[š]^™Y™XY\ÛÛÜ”™\Ù]
œÛÛ–Èœ™XY\ÛÛÜ”™\Ù]—H\ÏÈ[
CBˆ]™XY\•^[YÛ›Y[HœÛÛ–Èœ™XY\•^[YÛ›Y[—H\ÏÈİš[™ÈÏÈ›YƒBˆ]™XY\“[™TÜXÚ[™ÈH˜XÚİ\]KœØ[š]^™Y™XY\“[™TÜXÚ[™ÊBˆœÛÛ–Èœ™XY\“[™TÜXÚ[™È—H\ÏÈİX›CBˆ
CBˆ]™XY\“X\™Ú[ˆH˜XÚİ\]KœØ[š]^™Y™XY\“X\™Ú[ŠBˆœÛÛ–Èœ™XY\“X\™Ú[ˆ—H\ÏÈİX›CBˆ
CBƒBˆ]]]ĞÛX\ØXÚQ[˜X›YHœÛÛ–È˜]]ĞÛX\ØXÚQ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]]]ĞÛX\ØXÚU™\ÚÛPˆH˜XÚİ\]KœØ[š]^™Y]]ĞÛX\ØXÚU™\ÚÛPŠBˆœÛÛ–È˜]]ĞÛX\ØXÚU™\ÚÛPˆ—H\ÏÈİX›CBˆ
CBˆ]YÚ]X[]U™\ÚÛH˜XÚİ\]KœØ[š]^™YYÚ]X[]U™\ÚÛ
BˆœÛÛ–ÈšYÚ]X[]U™\ÚÛ—H\ÏÈİX›CBˆ
CBˆ]˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YHœÛÛ–È˜˜XÚÙÜ›İ[™Ô\[[™Q[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YHœÛÛ–Èœ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]™XY\‘İÛ›ØYÕÚYšSÛ›HHœÛÛ–Èœ™XY\‘İÛ›ØYÕÚYšSÛ›H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]™XY\‘İÛ›ØYÔ\˜[[[Z]H˜XÚİ\]KœØ[š]^™Y™XY\‘İÛ›ØYÔ\˜[[[Z]
˜XÚİ\]K›Ü[Û˜[[
œ›ÛNˆœÛÛ–Èœ™XY\‘İÛ›ØYÔ\˜[[[Z]—KY˜][˜[YNˆŠJCBˆ]]]Õ\]TÙ\šXÙ\Ñ[˜X›YHœÛÛ–È˜]]Õ\]TÙ\šXÙ\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]Ù\šXÙ\Ğ]]Ó[ÙQ[˜X›YHœÛÛ–ÈœÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈ]]Ó[ÙTÙ][™ÜË™Y˜][[˜X›YBˆ]Ù\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YHœÛÛ–ÈœÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›Y—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YHœÛÛ–ÈœÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙTÙ][™ÜË™Y˜][[˜X›YBˆ]Ù\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
˜XÚİ\]Kœİš[™Ó\İ
œ›ÛNˆœÛÛ–ÈœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈ—JJCBˆ]Ù\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
˜XÚİ\]Kœİš[™Ó\İ
œ›ÛNˆœÛÛ–ÈœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈ—JJCBˆ]Ù\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙHH]]Ó[ÙT]X[]T™Y™\™[˜ÙKœØ[š]^™Y˜]Õ˜[YJœÛÛ–ÈœÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙH—H\ÏÈİš[™ÊCBˆ]Ù\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]HH˜XÚİ\]KœØ[š]^™YÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]JBˆ˜XÚİ\]K›Ü[Û˜[İX›Jœ›ÛNˆœÛÛ–ÈœÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]H—KY˜][˜[YNˆÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË™Y˜][Z[š[][TÚ[Z[\š]JCBˆ
CBˆ]Ù\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ÈHœÛÛ–ÈœÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[È—H\ÏÈ›ÛÛÏÈÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË™Y˜][›ÜZ\ÛX]ÚY™\İ[ÃBˆ]Ù\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YHœÛÛ–ÈœÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›Y—H\ÏÈ›ÛÛÏÈÙ\šXÙ\ÔÚY]™\Ù[][Û”Ù][™ÜË™Y˜][İ™[Z[Ôİ[Q[˜X›YBˆ]Ù\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÈHİ™X[S[™İXYÙQš[\‹œØ[š]^™Y[™İXYÙS\İ
˜XÚİ\]Kœİš[™Ó\İ
œ›ÛNˆœÛÛ–ÈœÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\È—JJCBˆ]Ù\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÈHİ™X[S[™İXYÙQš[\‹œØ[š]^™Y[™İXYÙS\İ
˜XÚİ\]Kœİš[™Ó\İ
œ›ÛNˆœÛÛ–ÈœÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\È—JJCBˆ]Ù\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]HHœÛÛ–ÈœÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÈHœÛÛ–ÈœÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚHœÛÛ–ÈœÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\Ú—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù\šXÙ\ÒY[”İ™X[T]X[]Y\ÈHİ™X[S[™İXYÙQš[\‹œØ[š]^™Y]X[]RZYÚÊ˜XÚİ\]Kš[\İ
œ›ÛNˆœÛÛ–ÈœÙ\šXÙ\ÒY[”İ™X[T]X[]Y\È—JJCBˆ]Ù\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]HHœÛÛ–ÈœÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÎˆÔİš[™×OÃBˆYˆ]˜]ÔÛİ\˜ÙRYÈHœÛÛ–ÈœÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈ—H\ÏÈÔİš[™×HÃBˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈHİ™X[S[™İXYÙQš[\‹œØ[š]^™Y^˜T[\ÔÛİ\˜ÙRYÊ˜]ÔÛİ\˜ÙRYÊCBˆH[ÙHÃBˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈHš[BˆCBˆ]Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YHœÛÛ–È™Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›Y—H\ÏÈ›ÛÛÏÈYCBˆ]Ú]X”™[X\ÙU\]P]˜Z[X›HHœÛÛ–È™Ú]X”™[X\ÙU\]P]˜Z[X›H—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ú]X”™[X\ÙS]\İ™\œÚ[ÛˆHœÛÛ–È™Ú]X”™[X\ÙS]\İ™\œÚ[Ûˆ—H\ÏÈİš[™ÈÏÈˆƒBˆ]Ú]X”™[X\ÙUT“HœÛÛ–È™Ú]X”™[X\ÙUT“—H\ÏÈİš[™ÈÏÈˆƒBˆ]Ú]X”™[X\ÙTÚİĞ[\[™[™ÈHœÛÛ–È™Ú]X”™[X\ÙTÚİĞ[\[™[™È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆHœÛÛ–È™Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[Ûˆ—H\ÏÈİš[™ÈÏÈˆƒBˆ]š[\’Üœ›ÜÛÛ[HœÛÛ–È™š[\’Üœ›Üˆ—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]Ù[XİYÚ[Z[\š]P[ÛÜš]HH˜XÚİ\]KœØ[š]^™YÚ[Z[\š]P[ÛÜš]JœÛÛ–ÈœÙ[XİYÚ[Z[\š]P[ÛÜš]H—H\ÏÈİš[™ÊCBˆ]\™›Ü›X[˜ÙS[ÙQ[˜X›YHœÛÛ–Èœ\™›Ü›X[˜ÙS[ÙQ[˜X›Y—H\ÏÈ›ÛÛÏÈ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™Y˜][[˜X›YBˆ]\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ÈHœÛÛ–Èœ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[È—H\ÏÈ›ÛÛÏÈ˜[ÙCBˆ]˜]Ô\™›Ü›X[˜ÙS[ÙSİ™\œšY\ÈHœÛÛ–Èœ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\È—H\ÏÈÔİš[™Îˆ›ÛÛHÏÈÎ—CBˆ]\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\ÈH˜]Ô\™›Ü›X[˜ÙS[ÙSİ™\œšY\Ë™š[\ˆÈ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË˜[š[YPØ][ÙÒYË˜ÛÛZ[œÊ	šÙ^JHCBˆ]Ø[™[’ÛYTÙ[XİYÛİ\˜ÙRQHœÛÛ–ÈšØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQ—H\ÏÈİš[™ÈÏÈˆƒBˆ]Ø[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÈH˜XÚİ\]Kœİš[™Ó\İ
œ›ÛNˆœÛÛ–ÈšØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\È—JCBƒBˆËÈ[šY[™\İÜ™HX^HØ[˜YÙH[™\[™[šY[Ë]H\İXİ]™CBˆËÈÛXZ[ˆ\È]]Üš]]]™HÛ›HÚ[ˆ]È[\™H^[ØYXÛÙ\ËˆCBˆËÈX[›Ü›YYY[X™\ˆ]\İ›İ\›ˆH™\İ[ÈH\X[™\XÙ[Y[ƒBˆ]XÛÙYÛÛXİ[ÛœÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\ÛÛXİ[Û—KœÙ[‹Bˆœ›ÛNˆœÛÛ–È˜ÛÛXİ[ÛœÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙY›ÙÜ™\ÜÑ]HHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆ›ÙÜ™\ÜÑ]KœÙ[‹Bˆœ›ÛNˆœÛÛ–Èœ›ÙÜ™\ÜÑ]H—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙY˜XÚÙ\”İ]HHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆ˜XÚÙ\”İ]KœÙ[‹Bˆœ›ÛNˆœÛÛ–È˜XÚÙ\”İ]H—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYØ][ÙÜÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞØ][Ù×KœÙ[‹Bˆœ›ÛNˆœÛÛ–È˜Ø][ÙÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYÙ\šXÙ\ÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\Ù\šXÙWKœÙ[‹Bˆœ›ÛNˆœÛÛ–ÈœÙ\šXÙ\È—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]ÛÛXİ[ÛœÈHXÛÙYÛÛXİ[ÛœÈÏÈ×CBˆ]›ÙÜ™\ÜÑ]HHXÛÙY›ÙÜ™\ÜÑ]HÏÈ›ÙÜ™\ÜÑ]J
CBˆ]˜XÚÙ\”İ]HHXÛÙY˜XÚÙ\”İ]HÏÈ˜XÚÙ\”İ]J
CBˆ]Ø][ÙÜÈHXÛÙYØ][ÙÜÈÏÈ×CBˆ]Ù\šXÙ\ÈHXÛÙYÙ\šXÙ\ÈÏÈ×CBƒBˆ]İ™[Z[ĞYÛœÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\İ™[Z[ĞYÛ—KœÙ[‹Bˆœ›ÛNˆœÛÛ–Èœİ™[Z[ĞYÛœÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBƒBˆ˜\ˆÚŞTİ™X[NˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİÈHš[BˆYˆ]ÚŞTİ™X[U˜[YHHœÛÛ–ÈœÚŞTİ™X[H—KBˆ”ÓÓ”Ù\šX[^˜][Û‹š\Õ˜[Y”ÓÓ“Øš™Xİ
ÚŞTİ™X[U˜[YJKBˆ]ÚŞTİ™X[R”ÓÓˆHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™XİˆÚŞTİ™X[U˜[YJHÃBˆÚŞTİ™X[HHOÈ[šY[XÛÙ\‹™XÛÙJÚŞTİ™X[P˜XÚİ\Û˜\ÚİœÙ[‹œ›ÛNˆÚŞTİ™X[R”ÓÓŠCBˆCBƒBˆ˜\ˆ]š[ÔYÚ[œÎˆ]š[ÔİÜ™YYÚ[œÔİ]OÈHš[BˆYˆ]]š[Õ˜[YHHœÛÛ–È›]š[ÔYÚ[œÈ—KBˆ”ÓÓ”Ù\šX[^˜][Û‹š\Õ˜[Y”ÓÓ“Øš™Xİ
]š[Õ˜[YJKBˆ]]š[Ò”ÓÓˆHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™Xİˆ]š[Õ˜[YJHÃBˆ]š[ÔYÚ[œÈHOÈ[šY[XÛÙ\‹™XÛÙJ]š[ÔİÜ™YYÚ[œÔİ]KœÙ[‹œ›ÛNˆ]š[Ò”ÓÓŠCBˆCBƒBˆ]XÛÙYX[™ØPÛÛXİ[ÛœÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\X[™ØPÛÛXİ[Û—KœÙ[‹Bˆœ›ÛNˆœÛÛ–È›X[™ØPÛÛXİ[ÛœÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYX[™ØT™XY[™Ô›ÙÜ™\ÜÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÔİš[™ÎˆX[™ØT›ÙÜ™\Ü×KœÙ[‹Bˆœ›ÛNˆœÛÛ–È›X[™ØT™XY[™Ô›ÙÜ™\ÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYX[™ØPØ][ÙÜÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÓX[™ØPØ][Ù×KœÙ[‹Bˆœ›ÛNˆœÛÛ–È›X[™ØPØ][ÙÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYİ\İÛPØ][ÙÜÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÒØ[™[İ\İÛPØ][Ù×KœÙ[‹Bˆœ›ÛNˆœÛÛ–È˜İ\İÛPØ][ÙÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]XÛÙYØ[™[“[Ù[\ÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\Ø[™[“[Ù[WKœÙ[‹Bˆœ›ÛNˆœÛÛ–ÈšØ[™[“[Ù[\È—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]X[™ØPÛÛXİ[ÛœÈHXÛÙYX[™ØPÛÛXİ[ÛœÈÏÈ×CBˆ]X[™ØT™XY[™Ô›ÙÜ™\ÜÈHXÛÙYX[™ØT™XY[™Ô›ÙÜ™\ÜÈÏÈÎ—CBˆ]X[™ØPØ][ÙÜÈHXÛÙYX[™ØPØ][ÙÜÈÏÈ×CBˆ]İ\İÛPØ][ÙÜÈHXÛÙYİ\İÛPØ][ÙÜÈÏÈ×CBˆ]Ø[™[“[Ù[\ÈHXÛÙYØ[™[“[Ù[\ÈÏÈ×CBƒBˆ˜\ˆZYÚİTİ]Nˆ˜XÚİ\ZYÚİTİ]OÃBˆYˆ]ZYÚİQXİHœÛÛ–È˜ZYÚİTİ]H—H\ÏÈÔİš[™Îˆ[WKBˆ]]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™XİˆZYÚİQXİ
KBˆ]XÛÙYHOÈ[šY[XÛÙ\‹™XÛÙJ˜XÚİ\ZYÚİTİ]KœÙ[‹œ›ÛNˆ]JHÃBˆZYÚİTİ]HH˜XÚİ\]K˜ZYÚİTİ]UÚ]İ]^Xİ]X›T^[ØYÊXÛÙY
CBˆCBƒBˆ˜\ˆ™XY\‘^[œÚ[ÛœÔİ]Nˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]OÃBˆYˆ]™XY\‘^[œÚ[ÛœÑXİ[Û˜\HHœÛÛ–Èœ™XY\‘^[œÚ[ÛœÔİ]H—H\ÏÈÔİš[™Îˆ[WKBˆ]]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™Xİˆ™XY\‘^[œÚ[ÛœÑXİ[Û˜\JKBˆ]XÛÙYHOÈ[šY[XÛÙ\‹™XÛÙJ˜XÚİ\™XY\‘^[œÚ[Û”İ]KœÙ[‹œ›ÛNˆ]JHÃBˆ™XY\‘^[œÚ[ÛœÔİ]HHXÛÙYœØ[š]^™Y

CBˆH[ÙHYˆ]ZYÚİTİ]HÃBˆ™XY\‘^[œÚ[ÛœÔİ]HH˜XÚİ\™XY\‘^[œÚ[Û”İ]K›ZYÜ˜][™ÓYØXŞPZYÚİJZYÚİTİ]JCBˆCBƒBˆ]ÙX\˜Ú\İÜHH˜XÚİ\ÙX\˜Ú\İÜJœÛÛ•˜[YNˆœÛÛ–ÈœÙX\˜Ú\İÜH—JCBƒBˆ˜\ˆ™XÛÛ[Y[™][ÛØXÚNˆÕQ”ÙX\˜Ú™\İ[HH×CBˆYˆ]™XÜÑ]HHœÛÛ–Èœ™XÛÛ[Y[™][ÛØXÚH—H\ÏÈÖÔİš[™Îˆ[WWHÃBˆ›ÜˆXİ[ˆ™XÜÑ]HÃBˆYˆ]]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™XİˆXİ
KBˆ]™XÈHOÈ[šY[XÛÙ\‹™XÛÙJQ”ÙX\˜Ú™\İ[œÙ[‹œ›ÛNˆ]JHÃBˆ™XÛÛ[Y[™][ÛØXÚK˜\[™
™XÊCBˆCBˆCBˆCBƒBˆ]XÛÙY\Ù\”˜][™ÜÎˆÔİš[™ÎˆİX›WOÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÔİš[™ÎˆİX›WKœÙ[‹Bˆœ›ÛNˆœÛÛ–È\Ù\”˜][™ÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
HÏÈXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÔİš[™Îˆ[KœÙ[‹Bˆœ›ÛNˆœÛÛ–È\Ù\”˜][™ÜÈ—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
K›X\È	›X\˜[Y\ÊİX›Kš[š]
HCBˆ]XÛÙY\Ù\”˜][™Ó›İ\ÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆÔİš[™Îˆİš[™×KœÙ[‹Bˆœ›ÛNˆœÛÛ–È\Ù\”˜][™Ó›İ\È—KBˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
CBˆ]\Ù\”˜][™ÜÈH˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™ÜÊXÛÙY\Ù\”˜][™ÜÈÏÈÎ—JCBˆ]\Ù\”˜][™Ó›İ\ÈH˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™Ó›İ\ÊXÛÙY\Ù\”˜][™Ó›İ\ÈÏÈÎ—JCBƒBˆ]YYXTİ]TÙ][™ÜÈH˜XÚİ\]K›YYXTİ]TÙ][™ÜÊœ›ÛR”ÓÓ•˜[YNˆœÛÛ–È›YYXTİ]TÙ][™ÜÈ—JCBˆ]ÛÛXİ[ÛœÔ™\Ù[HXÛÙYÛÛXİ[ÛœÈOHš[Bˆ]›ÙÜ™\ÜÑ]T™\Ù[HXÛÙY›ÙÜ™\ÜÑ]HOHš[Bˆ]˜XÚÙ\”İ]T™\Ù[HXÛÙY˜XÚÙ\”İ]HOHš[Bˆ]Ø][ÙÜÔ™\Ù[HXÛÙYØ][ÙÜÈOHš[Bˆ]Ù\šXÙ\Ô™\Ù[HXÛÙYÙ\šXÙ\ÈOHš[Bˆ]X[™ØPÛÛXİ[ÛœÔ™\Ù[HXÛÙYX[™ØPÛÛXİ[ÛœÈOHš[Bˆ]X[™ØT™XY[™Ô›ÙÜ™\ÜÔ™\Ù[HXÛÙYX[™ØT™XY[™Ô›ÙÜ™\ÜÈOHš[Bˆ]X[™ØPØ][ÙÜÔ™\Ù[HXÛÙYX[™ØPØ][ÙÜÈOHš[Bˆ]İ\İÛPØ][ÙÜÔ™\Ù[HXÛÙYİ\İÛPØ][ÙÜÈOHš[Bˆ]Ø[™[“[Ù[\Ô™\Ù[HXÛÙYØ[™[“[Ù[\ÈOHš[Bˆ]\Ù\”˜][™ÜÔ™\Ù[HXÛÙY\Ù\”˜][™ÜÈOHš[	‰ˆXÛÙY\Ù\”˜][™Ó›İ\ÈOHš[BƒBˆ˜\ˆ[šY[H˜XÚİ\]JBˆ™\œÚ[Ûˆ™\œÚ[Û‹BˆÜ™X]Y]NˆÜ™X]Y]KBˆXØÙ[ÛÛÜˆXØÙ[ÛÛÜ‹BˆÙ][™ÜÑÜ˜YY[ÛÛÜˆÙ][™ÜÑÜ˜YY[ÛÛÜ‹Bˆ™XY\XØÙ[ÛÛÜˆ™XY\XØÙ[ÛÛÜ‹BˆY“[™İXYÙNˆY“[™İXYÙKBˆÙ[XİY\X\˜[˜ÙNˆÙ[XİY\X\˜[˜ÙKBˆ™XY\”Ù[XİY\X\˜[˜ÙNˆ™XY\”Ù[XİY\X\˜[˜ÙKBˆ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›Yˆ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YBˆ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜ‹Bˆ[˜X›TİX]\ĞQY˜][ˆ[˜X›TİX]\ĞQY˜][BˆY˜][İX]S[™İXYÙNˆY˜][İX]S[™İXYÙKBˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›Yˆ^Y\”İX]P\X\˜[˜ÙQ[˜X›YBˆ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙNˆ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙKBˆ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙNˆ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙKBˆ[\^Y\ˆ[\^Y\‹BˆÚİÔØÚY[UXˆÚİÔØÚY[UX‹BˆÚİÓØØ[ØÚY[U[YNˆÚİÓØØ[ØÚY[U[YKBˆY˜][ØÚY[S[ÙNˆY˜][ØÚY[S[ÙKBˆØÚY[UÚ[™İÑ^\ÎˆØÚY[UÚ[™İÑ^\ËBˆØØ[›İYšXØ][Û”İXœØÜš\[ÛœÎˆØØ[›İYšXØ][Û”İXœØÜš\[ÛœËBˆØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÎˆØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œËBˆØØ[›İYšXØ][Û‘\\ÛÙSXY[YNˆØØ[›İYšXØ][Û‘\\ÛÙSXY[YKBˆØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YNˆØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YKBˆØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÎˆØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ËBˆY˜][^X˜XÚÔÜYYˆY˜][^X˜XÚÔÜYYBˆÛÜYY^Y\ˆÛÜYY^Y\‹Bˆ^\›˜[^Y\ˆ^\›˜[^Y\‹Bˆ™Y™\‘İÛ›ØYYYYXNˆ™Y™\‘İÛ›ØYYYYXKBˆ[Ø^\Ó[™ØØ\Nˆ[Ø^\Ó[™ØØ\KBˆ^Y\”^X˜XÚÓØÚÑ[˜X›Yˆ^Y\”^X˜XÚÓØÚÑ[˜X›YBˆ[šTÚÚ\[˜X›Yˆ[šTÚÚ\[˜X›YBˆ[›Ñ‘[˜X›Yˆ[›Ñ‘[˜X›YBˆ[›Ñ\[˜X›Yˆ[›Ñ\[˜X›YBˆ[šTÚÚ\]]ÔÚÚ\ˆ[šTÚÚ\]]ÔÚÚ\BˆÚÚ\\Ñ[˜X›YˆÚÚ\\Ñ[˜X›YBˆÚÚ\\Ğ[Ø^\Õš\ÚX›NˆÚÚ\\Ğ[Ø^\Õš\ÚX›KBˆÚİÓ™^\\ÛÙP]ÛˆÚİÓ™^\\ÛÙP]Û‹BˆÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆÚİÑ\\ÛÙPœ›İÜÙ\]Û‹BˆÚİÔ^Y\”Ù\šXÙ\Ğ]ÛˆÚİÔ^Y\”Ù\šXÙ\Ğ]Û‹BˆÚİÓ™^\\ÛÙTÜİ\]ÛˆÚİÓ™^\\ÛÙTÜİ\]Û‹Bˆ™^\\ÛÙU™\ÚÛˆ™^\\ÛÙU™\ÚÛBˆ™^\\ÛÙTÚÚ\š[\‘[˜X›Yˆ™^\\ÛÙTÚÚ\š[\‘[˜X›YBˆ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›Yˆ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YBˆ^Y\•›Û[YQÙ\İ\™Q[˜X›Yˆ^Y\•›Û[YQÙ\İ\™Q[˜X›YBˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›Yˆ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YBˆ^Y\Ù[\•\^T]\ÙQ[˜X›Yˆ^Y\Ù[\•\^T]\ÙQ[˜X›YBˆ^Y\‘İX›U\ÙYZÑ[˜X›Yˆ^Y\‘İX›U\ÙYZÑ[˜X›YBˆ^Y\‘İX›U\ÙYZÔÙXÛÛ™Îˆ^Y\‘İX›U\ÙYZÔÙXÛÛ™ËBˆ^Y\“Ü[”İX]\Ñ[˜X›Yˆ^Y\“Ü[”İX]\Ñ[˜X›YBˆ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›Yˆ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YBˆ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›Yˆ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›YBˆ\‘›Ü™YÜ›İ[™”Îˆ\‘›Ü™YÜ›İ[™”ËBˆ\”™[™\˜XÚÙ[™ˆ\”™[™\˜XÚÙ[™Bˆ\“Y][]X[]T›Ùš[Nˆ\“Y][]X[]T›Ùš[KBˆ\•\ØØ[[™Ó[ÙNˆ\•\ØØ[[™Ó[ÙKBˆ\“™]\˜[\ØØ[\ˆ\“™]\˜[\ØØ[\‹Bˆ\“™]\˜[\ØØ[\•ˆ\“™]\˜[\ØØ[\•‹Bˆ\”^Y\”ÚÚ[ˆ\”^Y\”ÚÚ[‹Bˆ\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆ\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜ‹Bˆ\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆ\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜ‹Bˆ\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›Yˆ\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›YBˆ\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›Nˆ\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›KBˆ\”Xİ\™R[”Xİ\™Q[˜X›Yˆ\”Xİ\™R[”Xİ\™Q[˜X›YBˆ\\^]Xİ\™R[”Xİ\™Q[˜X›Yˆ\\^]Xİ\™R[”Xİ\™Q[˜X›YBˆ\’“[ÙNˆ\’“[ÙKBˆ\”İ\œ›İ[™Ûİ[™[˜X›Yˆ\”İ\œ›İ[™Ûİ[™[˜X›YBˆØ]ÚÙÙ]\‘[˜X›YˆØ]ÚÙÙ]\‘[˜X›YBˆÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YˆÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YBˆ^\š[Y[[™X]\™\Ñ[˜X›Yˆ^\š[Y[[™X]\™\Ñ[˜X›YBˆ^\š[Y[[™X]\™\Ó\İÚ[™ÙY]ˆ^\š[Y[[™X]\™\Ó\İÚ[™ÙY]Bˆ^\š[Y[[T”™[ØY[˜X›Yˆ^\š[Y[[T”™[ØY[˜X›YBˆ^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›Yˆ^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›YBˆ^\š[Y[[T”™[ØYÙ[[\‘[˜X›Yˆ^\š[Y[[T”™[ØYÙ[[\‘[˜X›YBˆ^\š[Y[[T”™[ØYÚYšS[Z]Pˆ^\š[Y[[T”™[ØYÚYšS[Z]P‹Bˆ^\š[Y[[T”™[ØYÙ[[\“[Z]Pˆ^\š[Y[[T”™[ØYÙ[[\“[Z]P‹Bˆ^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YNˆ^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YKBˆ^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜÎˆ^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜËBˆ^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\Îˆ^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\ËBˆ^\š[Y[[T”™[ØY]]ĞÛX\ˆ^\š[Y[[T”™[ØY]]ĞÛX\‹Bˆ^\š[Y[[PÛİYŞ[˜Ñ[˜X›Yˆ^\š[Y[[PÛİYŞ[˜Ñ[˜X›YBˆİX]Q›Ü™YÜ›İ[™ÛÛÜˆİX]Q›Ü™YÜ›İ[™ÛÛÜ‹BˆİX]Tİ›ÚÙPÛÛÜˆİX]Tİ›ÚÙPÛÛÜ‹BˆİX]Tİ›ÚÙUÚYˆİX]Tİ›ÚÙUÚYBˆİX]Q›ÛÚ^™NˆİX]Q›ÛÚ^™KBˆİX]U™\XØ[Ù™œÙ]ˆİX]U™\XØ[Ù™œÙ]BˆİX]\Õš\ÚX›NˆİX]\Õš\ÚX›KBˆÚİÒØ[™[ˆÚİÒØ[™[‹BˆYTÜ\ÚØÜ™Y[ˆYTÜ\ÚØÜ™Y[‹Bˆ[ÙTİÚ]Ú[š[X][Û‘[˜X›Yˆ[ÙTİÚ]Ú[š[X][Û‘[˜X›YBˆØ[™[]]Õ\]S[Ù[\ÎˆØ[™[]]Õ\]S[Ù[\ËBˆÙX\ÛÛ“Y[NˆÙX\ÛÛ“Y[KBˆÜš^›Û[\\ÛÙS\İˆÜš^›Û[\\ÛÙS\İBˆYYXQ]Z[]P\ÛÜšÑ[˜X›YˆYYXQ]Z[]P\ÛÜšÑ[˜X›YBˆYYXQ]Z[[\›˜]TÜİ\‘[˜X›YˆYYXQ]Z[[\›˜]TÜİ\‘[˜X›YBˆYYXQ]Z[Ú[Z[\•]\Ñ[˜X›YˆYYXQ]Z[Ú[Z[\•]\Ñ[˜X›YBˆ\ÙPÛ\ÜÚXÔØÚY[URNˆ\ÙPÛ\ÜÚXÔØÚY[URKBˆ\›Ğ˜[›™\Ø][ÙÒYˆ\›Ğ˜[›™\Ø][ÙÒYBˆ\›Ğ˜[›™\™Z]š[Üˆ\›Ğ˜[›™\™Z]š[Ü‹BˆÛYPØ][ÙÓ^[İ]İ™\œšY\ÎˆÛYPØ][ÙÓ^[İ]İ™\œšY\ËBˆÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YˆÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YBˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]NˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]KBˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]NˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]KBˆ\\™›Ü›X[˜ÙSİ™\›^Q[˜X›Yˆ\\™›Ü›X[˜ÙSİ™\›^Q[˜X›YBˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]ˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]Bˆ^\š[Y[[\›Ğ›YY]™[ˆ^\š[Y[[\›Ğ›YY]™[Bˆ^\š[Y[[ÛYPØ\™Ú\Nˆ^\š[Y[[ÛYPØ\™Ú\KBˆ^\š[Y[[][QÜ˜YY[[]Nˆ^\š[Y[[][QÜ˜YY[[]KBˆ^\š[Y[[\›ÒZYÚØØ[Nˆ^\š[Y[[\›ÒZYÚØØ[KBˆ^\š[Y[[\›Ğ›YYİ™[™İˆ^\š[Y[[\›Ğ›YYİ™[™İBˆ^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[Nˆ^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[KBˆ^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[Nˆ^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[KBˆ^\š[Y[[Ø\™˜Y]\ÔØØ[Nˆ^\š[Y[[Ø\™˜Y]\ÔØØ[KBˆ^\š[Y[[YYXPØ\™ØØ[Nˆ^\š[Y[[YYXPØ\™ØØ[KBˆ^\š[Y[[Û\ÜÔİ™[™İˆ^\š[Y[[Û\ÜÔİ™[™İBˆ^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÎˆ^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜËBˆ^\š[Y[[Ü˜YY[XØÙ[[[œÚ]Nˆ^\š[Y[[Ü˜YY[XØÙ[[[œÚ]KBˆ^\š[Y[[Ü˜YY[ØÜ›Û[İ[Ûˆ^\š[Y[[Ü˜YY[ØÜ›Û[İ[Û‹Bˆ^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœÎˆ^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœËBˆ^\š[Y[[Ü˜YY[ÛÛÜNˆ^\š[Y[[Ü˜YY[ÛÛÜKBˆ^\š[Y[[Ü˜YY[ÛÛÜˆ^\š[Y[[Ü˜YY[ÛÛÜ‹Bˆ^\š[Y[[Ü˜YY[ÛÛÜÎˆ^\š[Y[[Ü˜YY[ÛÛÜËBˆ][ÜÜ\™Tİ[Nˆ][ÜÜ\™Tİ[KBˆ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙNˆ][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙKBˆ][ÜÜ\™TÛÛYÛÛÜˆ][ÜÜ\™TÛÛYÛÛÜ‹Bˆ™XY\][ÜÜ\™Tİ[Nˆ™XY\][ÜÜ\™Tİ[KBˆ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙNˆ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙKBˆ™XY\][ÜÜ\™TÛÛYÛÛÜˆ™XY\][ÜÜ\™TÛÛYÛÛÜ‹BˆYYXQ]Z[[[Y[Ü™\ˆYYXQ]Z[[[Y[Ü™\‹BˆYYXQ]Z[Y[‘[[Y[ÎˆYYXQ]Z[Y[‘[[Y[ËBˆ™XY\‘]Z[[[Y[Ü™\ˆ™XY\‘]Z[[[Y[Ü™\‹Bˆ™XY\‘]Z[Y[‘[[Y[Îˆ™XY\‘]Z[Y[‘[[Y[ËBˆYYXPÛÛ[[œÔÜ˜Z]ˆYYXPÛÛ[[œÔÜ˜Z]BˆYYXPÛÛ[[œÓ[™ØØ\NˆYYXPÛÛ[[œÓ[™ØØ\KBˆ™XY[™Ó[ÙNˆ™XY[™Ó[ÙKBˆØ[™[”™XY\“[ÙNˆØ[™[”™XY\“[ÙKBˆØ[™[”™XY\“[ÙSİ™\œšY\ÎˆØ[™[”™XY\“[ÙSİ™\œšY\ËBˆ™XY\‘İÛœØ[\R[XYÙ\Îˆ™XY\‘İÛœØ[\R[XYÙ\ËBˆ™XY\Ü›Ü›Ü™\œÎˆ™XY\Ü›Ü›Ü™\œËBˆ™XY\‘\ØX›T]ZXÚĞXİ[ÛœÎˆ™XY\‘\ØX›T]ZXÚĞXİ[ÛœËBˆ™XY\‘\ØX›QİX›U\ˆ™XY\‘\ØX›QİX›U\Bˆ™XY\“]™U^ˆ™XY\“]™U^Bˆ™XY\’YP˜\œÓÛ”İÚ\Nˆ™XY\’YP˜\œÓÛ”İÚ\KBˆ™XY\˜XÚÙÜ›İ[™ÛÛÜˆ™XY\˜XÚÙÜ›İ[™ÛÛÜ‹Bˆ™XY\“ÜšY[][Ûˆ™XY\“ÜšY[][Û‹Bˆ™XY\•\›Û™\Îˆ™XY\•\›Û™\ËBˆ™XY\’[™\\›Û™\Îˆ™XY\’[™\\›Û™\ËBˆ™XY\[š[X]TYÙU˜[œÚ][ÛœÎˆ™XY\[š[X]TYÙU˜[œÚ][ÛœËBˆ™XY\•\ØØ[R[XYÙ\Îˆ™XY\•\ØØ[R[XYÙ\ËBˆ™XY\•\ØØ[SX^ZYÚˆ™XY\•\ØØ[SX^ZYÚBˆ™XY\•\ØØ[S[Ù[˜[YNˆ™XY\•\ØØ[S[Ù[˜[YKBˆ™XY\”YÙ\ÕÔ™[ØYˆ™XY\”YÙ\ÕÔ™[ØYBˆ™XY\”YÙYYÙS^[İ]ˆ™XY\”YÙYYÙS^[İ]Bˆ™XY\”YÙYYÙSÙ™œÙ]ˆ™XY\”YÙYYÙSÙ™œÙ]Bˆ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\Îˆ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ËBˆ™XY\”Ü]ÚYR[XYÙ\Îˆ™XY\”Ü]ÚYR[XYÙ\ËBˆ™XY\”™]™\œÙTÜ]Ü™\ˆ™XY\”™]™\œÙTÜ]Ü™\‹Bˆ™XY\•™\XØ[[™š[š]TØÜ›Ûˆ™XY\•™\XØ[[™š[š]TØÜ›ÛBˆ™XY\”[\˜›Şˆ™XY\”[\˜›ŞBˆ™XY\”[\˜›Ş[[İ[ˆ™XY\”[\˜›Ş[[İ[Bˆ™XY\”[\˜›ŞÜšY[][Ûˆ™XY\”[\˜›ŞÜšY[][Û‹Bˆ™XY\“ÜšY[][Û“ØÚÑ[˜X›Yˆ™XY\“ÜšY[][Û“ØÚÑ[˜X›YBˆ™XY\“ÜšY[][Û“ØÚÓX\ÚÎˆ™XY\“ÜšY[][Û“ØÚÓX\ÚËBˆ™XY\”™XY™\ÚÛ\˜Ù[ˆ™XY\”™XY™\ÚÛ\˜Ù[Bˆ™XY\‘›ÛÚ^™Nˆ™XY\‘›ÛÚ^™KBˆ™XY\‘›Û˜[Z[Nˆ™XY\‘›Û˜[Z[KBˆ™XY\‘›ÛÙZYÚˆ™XY\‘›ÛÙZYÚBˆ™XY\ÛÛÜ”™\Ù]ˆ™XY\ÛÛÜ”™\Ù]Bˆ™XY\•^[YÛ›Y[ˆ™XY\•^[YÛ›Y[Bˆ™XY\“[™TÜXÚ[™Îˆ™XY\“[™TÜXÚ[™ËBˆ™XY\“X\™Ú[ˆ™XY\“X\™Ú[‹Bˆ]]ĞÛX\ØXÚQ[˜X›Yˆ]]ĞÛX\ØXÚQ[˜X›YBˆ]]ĞÛX\ØXÚU™\ÚÛPˆ]]ĞÛX\ØXÚU™\ÚÛP‹BˆYÚ]X[]U™\ÚÛˆYÚ]X[]U™\ÚÛBˆ˜XÚÙÜ›İ[™Ô\[[™Q[˜X›Yˆ˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YBˆ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›Yˆ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YBˆ™XY\‘İÛ›ØYÕÚYšSÛ›Nˆ™XY\‘İÛ›ØYÕÚYšSÛ›KBˆ™XY\‘İÛ›ØYÔ\˜[[[Z]ˆ™XY\‘İÛ›ØYÔ\˜[[[Z]Bˆ]]Õ\]TÙ\šXÙ\Ñ[˜X›Yˆ]]Õ\]TÙ\šXÙ\Ñ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›YˆÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›YBˆÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YˆÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YˆÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›YBˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÎˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYËBˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÎˆÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YËBˆÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙNˆÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙKBˆÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]NˆÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]KBˆÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ÎˆÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ËBˆÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YˆÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›YBˆÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÎˆÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ËBˆÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÎˆÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ËBˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]NˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]KBˆÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÎˆÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ËBˆÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚˆÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚBˆÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ÎˆÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ËBˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]NˆÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]KBˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÎˆÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYËBˆÚ]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YˆÚ]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YBˆÚ]X”™[X\ÙU\]P]˜Z[X›NˆÚ]X”™[X\ÙU\]P]˜Z[X›KBˆÚ]X”™[X\ÙS]\İ™\œÚ[ÛˆÚ]X”™[X\ÙS]\İ™\œÚ[Û‹BˆÚ]X”™[X\ÙUT“ˆÚ]X”™[X\ÙUT“BˆÚ]X”™[X\ÙTÚİĞ[\[™[™ÎˆÚ]X”™[X\ÙTÚİĞ[\[™[™ËBˆÚ]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆÚ]X”™[X\ÙS\İ›Û\Y™\œÚ[Û‹Bˆš[\’Üœ›ÜÛÛ[ˆš[\’Üœ›ÜÛÛ[BˆÙ[XİYÚ[Z[\š]P[ÛÜš]NˆÙ[XİYÚ[Z[\š]P[ÛÜš]KBˆ\™›Ü›X[˜ÙS[ÙQ[˜X›Yˆ\™›Ü›X[˜ÙS[ÙQ[˜X›YBˆ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[Îˆ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ËBˆ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\Îˆ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\ËBˆØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQˆØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQBˆØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÎˆØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ËBˆÛÛXİ[ÛœÎˆÛÛXİ[ÛœËBˆ›ÙÜ™\ÜÑ]Nˆ›ÙÜ™\ÜÑ]KBˆ˜XÚÙ\”İ]Nˆ˜XÚÙ\”İ]KBˆØ][ÙÜÎˆØ][ÙÜËBˆÙ\šXÙ\ÎˆÙ\šXÙ\ËBˆİ™[Z[ĞYÛœÎˆİ™[Z[ĞYÛœËBˆÚŞTİ™X[NˆÚŞTİ™X[KBˆ]š[ÔYÚ[œÎˆ]š[ÔYÚ[œËBˆX[™ØPÛÛXİ[ÛœÎˆX[™ØPÛÛXİ[ÛœËBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÎˆX[™ØT™XY[™Ô›ÙÜ™\ÜËBˆX[™ØPØ][ÙÜÎˆX[™ØPØ][ÙÜËBˆİ\İÛPØ][ÙÜÎˆİ\İÛPØ][ÙÜËBˆØ[™[“[Ù[\ÎˆØ[™[“[Ù[\ËBˆ™XY\‘^[œÚ[ÛœÔİ]Nˆ™XY\‘^[œÚ[ÛœÔİ]KBˆZYÚİTİ]NˆZYÚİTİ]KBˆÙX\˜Ú\İÜNˆÙX\˜Ú\İÜKBˆ™XÛÛ[Y[™][ÛØXÚNˆ™XÛÛ[Y[™][ÛØXÚKBˆ\Ù\”˜][™ÜÎˆ\Ù\”˜][™ÜËBˆ\Ù\”˜][™Ó›İ\Îˆ\Ù\”˜][™Ó›İ\ËBˆYYXTİ]TÙ][™ÜÎˆYYXTİ]TÙ][™ÜËBˆÛÛXİ[ÛœÔ™\Ù[ˆÛÛXİ[ÛœÔ™\Ù[Bˆ›ÙÜ™\ÜÑ]T™\Ù[ˆ›ÙÜ™\ÜÑ]T™\Ù[Bˆ˜XÚÙ\”İ]T™\Ù[ˆ˜XÚÙ\”İ]T™\Ù[BˆØ][ÙÜÔ™\Ù[ˆØ][ÙÜÔ™\Ù[BˆÙ\šXÙ\Ô™\Ù[ˆÙ\šXÙ\Ô™\Ù[BˆX[™ØPÛÛXİ[ÛœÔ™\Ù[ˆX[™ØPÛÛXİ[ÛœÔ™\Ù[BˆX[™ØT™XY[™Ô›ÙÜ™\ÜÔ™\Ù[ˆX[™ØT™XY[™Ô›ÙÜ™\ÜÔ™\Ù[BˆX[™ØPØ][ÙÜÔ™\Ù[ˆX[™ØPØ][ÙÜÔ™\Ù[Bˆİ\İÛPØ][ÙÜÔ™\Ù[ˆİ\İÛPØ][ÙÜÔ™\Ù[BˆØ[™[“[Ù[\Ô™\Ù[ˆØ[™[“[Ù[\Ô™\Ù[Bˆ\Ù\”˜][™ÜÔ™\Ù[ˆ\Ù\”˜][™ÜÔ™\Ù[Bˆ
CBƒBˆYˆ]›Ùš[\Ò”ÓÓˆHœÛÛ–Èœ›Ùš[\È—KJ›Ùš[\Ò”ÓÓˆ\È”Ó[
HÃBˆİX\™]XÛÙY›Ùš[\ÈHXÛÙP˜XÚİ\”ÓÓ•˜[YJBˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİKœÙ[‹Bˆœ›ÛNˆ›Ùš[\Ò”ÓÓ‹Bˆ\Ú[™Îˆ[šY[XÛÙ\ƒBˆ
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“[šY[XÛÙH™Y\ÙY[ˆ[œ™XYX›H›Ùš[H›Üİ\ˆ‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆš[BˆCBˆ[šY[œ›Ùš[\ÈHXÛÙY›Ùš[\ÃBˆH[ÙHYˆœÛÛ–Èœ›Ùš[\È—H\È”Ó[ÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ“[šY[XÛÙH›İ[™H[›Ùš[H›Üİ\ÈÛ›H[™\[™[H]]Üš]]]™HÜ[]™[ÛXZ[œÈØ[ˆ™\İÜ™H‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆCBˆ[šY[˜Xİ]™T›Ùš[RQH
œÛÛ–È˜Xİ]™T›Ùš[RQ—H\ÏÈİš[™ÊK™›]X\
URQš[š]
]ZYİš[™ÎŠJCBƒBˆ[šY[œÚ\™\ÔÙ\šXÙ\ÈHœÛÛ–ÈœÚ\™\ÔÙ\šXÙ\È—H\ÏÈ›ÛÛBˆYˆ]Ù\šXÙ\Ò”ÓÓˆHœÛÛ–ÈœÙ\šXÙ\ÔÙ][™ÜÈ—KBˆ]Ù\šXÙ\Ñ]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™XİˆÙ\šXÙ\Ò”ÓÓŠKBˆ]XÛÙYÙ\šXÙ\ÈHOÈ[šY[XÛÙ\‹™XÛÙJÔİš[™Îˆ]WKœÙ[‹œ›ÛNˆÙ\šXÙ\Ñ]JHÃBˆ[šY[œÙ\šXÙ\ÔÙ][™ÜÈHXÛÙYÙ\šXÙ\ÃBˆCBƒBˆYˆ]^[ØYÒ”ÓÓˆHœÛÛ–ÈœÚŞTİ™X[TÚ\™Y^[ØYÈ—KBˆ]^[ØYÑ]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™Xİˆ^[ØYÒ”ÓÓŠKBˆ]XÛÙYHOÈ[šY[XÛÙ\‹™XÛÙJĞ˜XÚİ\ÚŞTİ™X[TÚ\™Y^[ØYKœÙ[‹œ›ÛNˆ^[ØYÑ]JHÃBˆ[šY[œÚŞTİ™X[TÚ\™Y^[ØYÈHXÛÙYBˆCBˆYˆ]^[ØYÒ”ÓÓˆHœÛÛ–È›]š[ÔÚ\™Y^[ØYÈ—KBˆ]^[ØYÑ]HHOÈ”ÓÓ”Ù\šX[^˜][Û‹™]JÚ]”ÓÓ“Øš™Xİˆ^[ØYÒ”ÓÓŠKBˆ]XÛÙYHOÈ[šY[XÛÙ\‹™XÛÙJĞ˜XÚİ\]š[ÔÚ\™Y^[ØYKœÙ[‹œ›ÛNˆ^[ØYÑ]JHÃBˆ[šY[›]š[ÔÚ\™Y^[ØYÈHXÛÙYBˆCBˆ[šY[˜[Ü]™[Ù][™ÜÕÙ\™PØ\\™YH˜[ÙCBˆ]XÛÙYÙ][™ÒÙ^\ÈH˜XÚİ\]K™XÛÙYÜ]™[Ù][™ÒÙ^\ÊBˆœ›ÛR”ÓÓ“Øš™XİˆœÛÛƒBˆ
CBˆYˆœÛÛ‹šÙ^\Ë˜ÛÛZ[œÊÜ]™[Ù][™ÒÙ^\ÈŠHÃBˆ[šY[™XÛÙYÜ]™[Ù][™ÒÙ^\ÈHXÛÙYÙ][™ÒÙ^\Ëš[\œÙXİ[ÛŠBˆ˜XÚİ\]KœØ[š]^™YXÛ\™YÜ]™[Ù][™ÒÙ^\ÊBˆœÛÛ–ÈÜ]™[Ù][™ÒÙ^\È—H\ÏÈÔİš[™×CBˆ
CBˆ
CBˆH[ÙHÃBˆ[šY[™XÛÙYÜ]™[Ù][™ÒÙ^\ÈHXÛÙYÙ][™ÒÙ^\ÃBˆCBˆ™]\›ˆ[šY[BˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™\İÜ™S]š[ÔÛ˜\ÚİY”İ\ÜY
BˆÈÛ˜\Úİˆ]š[ÔİÜ™YYÚ[œÔİ]OËBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[‹Bˆ™\Ù\š[™Ñ]šXÙSØØ[ÛİYİ]Nˆ›ÛÛH˜[ÙCBˆ
H\Ş[˜ÈOˆ›ÛÛÃBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]Û˜\Úİ[ÙHÈ™]\›ˆYHCBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆİX\™]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÓ]š[ÔYÚ[œÈ[ÙHÈ™]\›ˆYHCBˆ]X[˜YÙ\ˆH]š[ÔYÚ[“X[˜YÙ\‹œÚ\™YBˆX[˜YÙ\‹›ØY

CBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]İ]UÔ™\İÜ™Nˆ]š[ÔİÜ™YYÚ[œÔİ]CBˆYˆ™\Ù\š[™Ñ]šXÙSØØ[ÛİYİ]HÃBˆİ]UÔ™\İÜ™HH˜XÚİ\]K›]š[Ô™\İÜ™T[‘›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆ[˜ÛÛZ[™ÎˆÛ˜\ÚİBˆİ\œ™[ˆX[˜YÙ\‹˜˜XÚİ\İ]J
HÏÈ]š[ÔİÜ™YYÚ[œÔİ]J
CBˆ
Kœİ]CBˆH[ÙHÃBˆİ]UÔ™\İÜ™HHÛ˜\ÚİBˆCBˆ]™\İ[H]ØZ]X[˜YÙ\‹œ™\İÜ™P˜XÚİ\İ]JBˆİ]UÔ™\İÜ™KBˆ^XİYØÛÜQÙ[™\˜][Ûˆ^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
CBˆİX\™™\İ[œ™\İÜ™UØ\Ô\œÚ\İY\™\İ[Ø\Ò[\œ\Y[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[™YƒBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][ÛƒBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™\İÜ™TÚŞTİ™X[TÛ˜\Úİ[™ØZ]Y”İ\ÜY
BˆÈÛ˜\ÚİˆÚŞTİ™X[P˜XÚİ\Û˜\ÚİËBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ
H\Ş[˜ÈOˆ›ÛÛÃBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆİX\™]Û˜\Úİ[ÙHÈ™]\›ˆYHCBƒBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆYˆT]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÔÚŞTİ™X[TYÚ[œÈÃBˆÈÃBƒBˆH\œÚ\İÜ\]YTÚŞTİ™X[TÛ˜\Úİ
Û˜\Úİ
CBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][ÛƒBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘˜Z[YÈ™\Ù\™H\ØX›YÚŞTİ™X[H™\İÜ™H\œ›Ü•\OW
İš[™Ê™Y›Xİ[™Îˆ\JÙˆ\œ›ÜŠJJH‹Bˆ\NˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈÛİYŞ[˜Èˆˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆCBˆ]ØY™TÛ˜\ÚİHÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİBˆÈ˜XÚİ\]KœÚŞTİ™X[TÛ˜\Úİ›Ü‘^\š[Y[[ÛİYŞ[˜ÊÛ˜\Úİ
CBˆˆš[BˆYˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİØY™TÛ˜\ÚİOHš[ÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ”™Y\ÙY[˜[YØY™HÚŞTİ™X[H˜XÚİ\Y]Y]H‹\NˆÛİYŞ[˜ÈŠCBˆ™]\›ˆ˜[ÙCBˆCBƒBˆ]X[˜YÙ\ˆHÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™YBˆ]ØZ]X[˜YÙ\‹œ™[ØY\œÚ\İYİ]PY\”™\İÜ™J
CBˆİX\™X[˜YÙ\‹š\ÓØYYU\ÚËš\ĞØ[˜Ù[YBˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ]ÛÛ^HÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈ˜ÛİYY]Y]HY\™ÙHˆˆ›X[X[™\İÜ™HƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”ÚŞTİ™X[H
ÛÛ^
HÚÚ\Y™XØ]\ÙHHYÚ[ˆX[˜YÙ\ˆY›İš[š\ÚØY[™È‹Bˆ\NˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈÛİYŞ[˜Èˆˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÈÃBˆYˆ]ØY™TÛ˜\ÚİÃBˆ]™\İ[HH]ØZ]X[˜YÙ\‹œ™\İÜ™TØY™PÛİYÛ˜\Úİ
ØY™TÛ˜\Úİ
CBˆYˆ™\İ[š\ĞÛÛ\]HÃBˆÛX\YÜYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
\ÔØY™PÛİYÛ˜\ÚİˆYJCBˆÙÙÙ\‹œÚ\™Y›ÙÊ”ØY™HÚŞTİ™X[HÛİYY]Y]HY\™ÙY‹\NˆÛİYŞ[˜ÈŠCBˆH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”ØY™HÚŞTİ™X[HÛİYY]Y]H\X[HY\™ÙY[œ™\ÛÛ™YÛİ[W
™\İ[[œ™\ÛÛ™YXÚØYÙRQË˜Ûİ[
H‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆCBˆH[ÙHÃBˆH]ØZ]X[˜YÙ\‹œ™\İÜ™SX[X[˜XÚİ\Û˜\Úİ
Û˜\Úİ
CBˆÛX\YÜYÜ\]YTÚŞTİ™X[TÛ˜\Úİ
\ÔØY™PÛİYÛ˜\Úİˆ˜[ÙJCBˆÙÙÙ\‹œÚ\™Y›ÙÊ]]Üš]]]™HÚŞTİ™X[HX[X[˜XÚİ\™\İÜ™Y‹\Nˆ’[™›ÈŠCBˆCBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][ÛƒBˆHØ]ÚÃBˆ]ÛÛ^HÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈ˜ÛİYY]Y]HY\™ÙHˆˆ›X[X[™\İÜ™HƒBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘˜Z[YÚŞTİ™X[H
ÛÛ^
H\œ›Ü•\OW
İš[™Ê™Y›Xİ[™Îˆ\JÙˆ\œ›ÜŠJJH‹Bˆ\NˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈÛİYŞ[˜Èˆˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[ÙCBˆÈÃBƒBˆH\œÚ\İÜ\]YTÚŞTİ™X[TÛ˜\Úİ
Û˜\Úİ
CBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][ÛƒBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ‘˜Z[YÈ™\Ù\™HÜ\]YHÚŞTİ™X[H˜XÚİ\\œ›Ü•\OW
İš[™Ê™Y›Xİ[™Îˆ\JÙˆ\œ›ÜŠJJH‹Bˆ\NˆÛ˜\Úİš\ÔØY™PÛİYÛ˜\ÚİÈÛİYŞ[˜Èˆˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[™YƒBˆCBƒBˆš]˜]H[˜È™\Z\Xİ]™T›Ùš[TÚŞTİ™X[Tİ]RY“™YYY
BˆÈ˜XÚİ\ˆ˜XÚİ\]KBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ
H\Ş[˜ÈÃBˆİX\™T›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\È[ÙHÈ™]\›ˆCBƒBˆİX\™Xİ]™T›Ùš[TØÛÜR\Ğİ\œ™[
^XİYØÛÜK[˜ÛY[™Ô›Üİ\ˆ˜[ÙJH[ÙHÈ™]\›ˆCBˆ]Xİ]™T›Ùš[RQH^XİYØÛÜKœ›Ùš[RQBˆİX\™]İÛ™\ˆH˜XÚİ\˜Xİ]™T›Ùš[RQİÛ™\ˆOHXİ]™T›Ùš[RQ[ÙHÈ™]\›ˆCBˆİX\™]İ]Q]HH˜XÚİ\œ›Ùš[\ÏÃBˆ™š\œİ
Ú\™NˆÈ	šYOHXİ]™T›Ùš[RQJOÃBˆœÚŞTİ™X[Tİ]Q]H[ÙHÈ™]\›ˆCBˆÈÃBˆH]ØZ]Ù\šXÙTİÜ™KœÚ\™YœØ]™TÚŞTİ™X[Tİ]Q]JBˆİ]Q]KBˆ^XİYØÛÜQÙ[™\˜][Ûˆ^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÛİ[›İ™\İÜ™HHXİ]™H›Ùš[IÜÈİÛˆÚŞTİ™X[Hİ]HY\ˆ[ˆİÛ™\‹[Z\ÛX]ÚY™\İÜ™Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ƒBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ\YYHXİ]™H›Ùš[IÜÈİÛˆÚŞTİ™X[Hİ]Hİ™\ˆHÜ[]™[İÛ™\‰ÜÈ

İÛ™\ŠJH‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBƒBˆš]˜]H[˜È\Y\ÕÜ]™[Ûİ\˜ÙQ]JÈ˜XÚİ\ˆ˜XÚİ\]KXİ]™T›Ùš[RQˆURQ
HOˆ›ÛÛÃBˆYˆ˜XÚİ\œÚ\™\ÔÙ\šXÙ\ÈÏÈ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÈÈ™]\›ˆYHCBƒBˆİX\™İ\œ™[›Ùš[T›Üİ\’\Ô™XYX›J
H[ÙHÈ™]\›ˆ˜[ÙHCBˆİX\™]İÛ™\ˆH˜XÚİ\˜Xİ]™T›Ùš[RQ[ÙHÈ™]\›ˆYHCBˆ™]\›ˆİÛ™\ˆOHXİ]™T›Ùš[RQBˆCBƒBˆš]˜]H[˜Èİ\œ™[Xİ]™T›Ùš[RQ

HOˆURQÃBˆ˜\ˆYH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQBˆ\™›Ü›SÛ“XZ[•™XYÃBˆYH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆCBˆ™]\›ˆYBˆCBƒBˆš]˜]H[˜Èİ\œ™[›Ùš[T›Üİ\’\Ô™XYX›J
HOˆ›ÛÛÃBˆ˜\ˆ\Ô™XYX›HH˜[ÙCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ\Ô™XYX›HH›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\”İÜ™R\Ô™XYX›CBˆCBˆ™]\›ˆ\Ô™XYX›CBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È\P˜XÚİ\]RY”ØÛÜR\Ğİ\œ™[
BˆÈ˜XÚİ\ˆ˜XÚİ\]KBˆ™Yœ™\ÚÛİYÛİ\˜Ù\Îˆ›ÛÛH˜[ÙKBˆ™\Ù\š[™ÓYØXŞPÛİYYYXTİ]Nˆ›ÛÛH˜[ÙKBˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[Ûˆ›ÛÛH˜[ÙKBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ
HOˆØÛÜY˜XÚİ\\XØ][Û”™\İ[ÈÃBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆX›ÜY™\İÜ™H™XØ]\ÙHHXİ]™H›Ùš[HÚ[™ÙY‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆš[BˆCBˆ]YYXTİ]P]]Üš]HH™\Ù\š[™ÓYØXŞPÛİYYYXTİ]CBˆÈØ\\™SYØXŞPÛİYYYXTİ]P]]Üš]J
CBˆˆš[Bˆ]\XØ][ÛˆH\P˜XÚİ\]JBˆ˜XÚİ\Bˆ™Yœ™\ÚÛİYÛİ\˜Ù\Îˆ™Yœ™\ÚÛİYÛİ\˜Ù\ËBˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]Nˆ™\Ù\š[™ÓYØXŞPÛİYYYXTİ]KBˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[Ûˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[ÛƒBˆ
CBˆYˆ]YYXTİ]P]]Üš]HÃBˆ™\İÜ™SYØXŞPÛİYYYXTİ]P]]Üš]JYYXTİ]P]]Üš]JCBˆCBˆİX\™]\XØ][Ûˆ[ÙHÈ™]\›ˆš[CBˆ\™›Ü›SÛ“XZ[•™XYÃBˆÛYPØ][ÙÓ^[İ]İÜ™KœÚ\™Yœ™[ØYœ›ÛTİÜ˜YÙJ
CBˆXÛ\ÙU[YKœÚ\™Yœ™[ØY›ÜXİ]™T›Ùš[J
CBˆ[ÛÜš]SX[˜YÙ\‹œÚ\™Yœ™[ØY›ÜXİ]™T›Ùš[J
CBˆXØÙ[ÛÛÜ“X[˜YÙ\‹œÚ\™Yœ™[ØY›ÜXİ]™T›Ùš[J
CBˆÙ][™ÜË˜İ\œ™[Ëœ™[ØY›ÜXİ]™T›Ùš[J
CBˆCBƒBˆ™]\›ˆØÛÜY˜XÚİ\\XØ][Û”™\İ[
BˆØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ŠBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆÙ\šXÙ\ÑÙ[™\˜][ÛˆÙ\šXÙTİÜ™TØÛÜK™Ù[™\˜][Û‹Bˆ›Üİ\‘Ù[™\˜][Ûˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛƒBˆ
KBˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆ\XØ][Û‹˜]]Üš]]]™U˜XÚÙ\”›Ùš[RQÃBˆ
CBˆCBƒBˆš]˜]H[˜È\TÚ\™TÙ\šXÙ\Ó[ÙRY“™YYY
È˜XÚİ\ˆ˜XÚİ\]JHÃBˆİX\™]Ú\™\ÔÙ\šXÙ\ÈH˜XÚİ\œÚ\™\ÔÙ\šXÙ\ËBˆÚ\™\ÔÙ\šXÙ\ÈOH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\È[ÙHÈ™]\›ˆCBˆ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÈHÚ\™\ÔÙ\šXÙ\ÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆÙ\šXÙTİÜ™TØÛÜK˜Xİ]™T›Ùš[QYÚ[™ÙJ
CBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ\YYH˜XÚİ\	ÜÈÚ\™HÙ\šXÙ\È[ÙH

Ú\™\ÔÙ\šXÙ\ÊJH™Y›Ü™H™\İÜš[™ÈÛİ\˜Ù\È‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™YÚ[”Ú\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆ›Üˆ˜XÚİ\ˆ˜XÚİ\]KBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[ƒBˆ
H›İÜÈOˆÚ\™TÙ\šXÙ\Ô™\İÜ™Tİ\ÃBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ›İÈ˜XÚİ\™\İÜ™Q\œ›Ü‹˜Xİ]™T›Ùš[PÚ[™ÙYBˆCBˆ]™]š[İ\Õ˜[YHH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆ]™\]Y\İY˜[YHH˜XÚİ\œÚ\™\ÔÙ\šXÙ\ÈÏÈ™]š[İ\Õ˜[YCBˆ]Xİ]™T›Ùš[RQH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆ]\™Ù]\Ù\ÔÚ\™YY˜][ÈH™\]Y\İY˜[YCBˆXİ]™T›Ùš[RQOH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQBˆ]\™Ù]İÜ™UT“H\™Ù]\Ù\ÔÚ\™YY˜][ÃBˆÈÙ\šXÙTİÜ™TØÛÜKœÚ\™YİÜ™UT“BˆˆÙ\šXÙTİÜ™TØÛÜKœØÛÜYİÜ™UT“
›Ü”›Ùš[NˆXİ]™T›Ùš[RQ
CBƒBˆÙ\šXÙTİÜ™TØÛÜKÚ[Ú[™ÙPXİ]™T›Ùš[J
CBˆ]\™Ù]İÜ™TÛ˜\ÚİHHÙ\šXÙTİÜ™TØÛÜK˜Ø\\™TİÜ™Qš[TÛ˜\Úİ
Bˆ]ˆ\™Ù]İÜ™UT“BˆØÛÜY˜][›Ùš[RQˆ\™Ù]\Ù\ÔÚ\™YY˜][ÈÈš[ˆXİ]™T›Ùš[RQBˆ
CBˆ]\™Ù]Ù][™ÜÈHØ\\™TÙ\šXÙ\ÔÙ][™ÜÑ›Ü”›Û˜XÚÊBˆ›Ùš[RQˆXİ]™T›Ùš[RQBˆ\Ù\ÔÚ\™YY˜][Îˆ\™Ù]\Ù\ÔÚ\™YY˜][ÃBˆ
CBˆ]˜[œØXİ[ÛˆHÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆ™]š[İ\Õ˜[YNˆ™]š[İ\Õ˜[YKBˆ™\]Y\İY˜[YNˆ™\]Y\İY˜[YKBˆXİ]™T›Ùš[RQˆXİ]™T›Ùš[RQBˆ\™Ù]\Ù\ÔÚ\™YY˜][Îˆ\™Ù]\Ù\ÔÚ\™YY˜][ËBˆ\™Ù]İÜ™TÛ˜\Úİˆ\™Ù]İÜ™TÛ˜\ÚİBˆ\™Ù]Ù][™ÜĞ™Y›Ü™U˜[œÚ][Ûˆ\™Ù]Ù][™ÜÃBˆ
CBƒBˆYˆ˜[œØXİ[Û‹™YİÚ]ÚÃBˆ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÈH™\]Y\İY˜[YCBˆÙ\šXÙTİÜ™TØÛÜK˜Xİ]™T›Ùš[QYÚ[™ÙJ›İYSØœÙ\™\œÎˆ˜[ÙJCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ\YYH˜XÚİ\	ÜÈÚ\™HÙ\šXÙ\È[ÙH

™\]Y\İY˜[YJJH™Y›Ü™H™\İÜš[™ÈÛİ\˜Ù\È‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBˆ]Üİ˜[œÚ][Û”ØÛÜHHXİ]™T›Ùš[TØÛÜUÚÙ[ŠBˆ›Ùš[RQˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQBˆÙ\šXÙ\ÑÙ[™\˜][ÛˆÙ\šXÙTİÜ™TØÛÜK™Ù[™\˜][Û‹Bˆ›Üİ\‘Ù[™\˜][Ûˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛƒBˆ
CBˆİX\™˜[œØXİ[Û‹˜Xİ]™T›Ùš[RQOHÜİ˜[œÚ][Û”ØÛÜKœ›Ùš[RQBˆÜİ˜[œÚ][Û”ØÛÜKœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ›İÈ˜XÚİ\™\İÜ™Q\œ›Ü‹˜Xİ]™T›Ùš[PÚ[™ÙYBˆCBˆ™]\›ˆÚ\™TÙ\šXÙ\Ô™\İÜ™Tİ\
Bˆ˜[œØXİ[Ûˆ˜[œØXİ[Û‹BˆØÛÜNˆÜİ˜[œÚ][Û”ØÛÜCBˆ
CBˆCBƒBˆš]˜]H[˜ÈØ\\™TÙ\šXÙ\ÔÙ][™ÜÑ›Ü”›Û˜XÚÊBˆ›Ùš[RQˆURQBˆ\Ù\ÔÚ\™YY˜][Îˆ›ÛÛBˆ
HOˆÔİš[™Îˆ]WHÃBˆ]ÛXZ[“˜[YHH\Ù\ÔÚ\™YY˜][ÃBˆÈ
[™K›XZ[‹˜[™RY[YšY\ˆÏÈ˜\‘XÛ\ÙHŠCBˆˆ›Ùš[TÙ][™ÜÔİÜ™KœİZ]S˜[YJ›Üˆ›Ùš[RQ
CBˆ]ÛXZ[ˆH\Ù\‘Y˜][Ëœİ[™\™œ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆÛXZ[“˜[YJHÏÈÎ—CBˆ™]\›ˆÛXZ[‹œ™YXÙJ[ÎˆÔİš[™Îˆ]WJ
JHÈ™\İ[[H[ƒBˆİX\™[KšÙ^HOH™XÛ\ÙTÙ\šXÙ\ÔÙ][™ÜÔÙYYYŒHƒBˆXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›Üˆ[KšÙ^JHOHœÙ\šXÙ\ËBˆ]]HHOÈ›Ü\S\İÙ\šX[^˜][Û‹™]JBˆœ›ÛT›Ü\S\İˆ[K˜[YKBˆ›Ü›X]ˆ˜š[˜\KBˆÜ[ÛœÎˆBˆ
H[ÙHÈ™]\›ˆCBˆ™\İ[Ù[KšÙ^WHH]CBˆCBˆCBƒBˆš]˜]H[˜È™\İÜ™TÙ\šXÙ\ÔÙ][™ÜĞY\‘˜Z[Y˜[œÚ][ÛŠBˆÈ˜[œØXİ[ÛˆÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛƒBˆ
HÃBˆ]›Ùš[RQH˜[œØXİ[Û‹˜Xİ]™T›Ùš[RQBˆ]İÜ™HH˜[œØXİ[Û‹\™Ù]\Ù\ÔÚ\™YY˜][ÃBˆÈ\Ù\‘Y˜][Ëœİ[™\™Bˆˆ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™YœİÜ™J›Üˆ›Ùš[RQ
CBˆ]ÛXZ[“˜[YHH˜[œØXİ[Û‹\™Ù]\Ù\ÔÚ\™YY˜][ÃBˆÈ
[™K›XZ[‹˜[™RY[YšY\ˆÏÈ˜\‘XÛ\ÙHŠCBˆˆ›Ùš[TÙ][™ÜÔİÜ™KœİZ]S˜[YJ›Üˆ›Ùš[RQ
CBˆ]İ\œ™[ÛXZ[ˆH\Ù\‘Y˜][Ëœİ[™\™œ\œÚ\İ[ÛXZ[Š›Ü“˜[YNˆÛXZ[“˜[YJHÏÈÎ—CBˆ›ÜˆÙ^H[ˆİ\œ™[ÛXZ[‹šÙ^\ÈÚ\™HÙ^HOH™XÛ\ÙTÙ\šXÙ\ÔÙ][™ÜÔÙYYYŒHƒBˆXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœÙ\šXÙ\ÈÃBˆİÜ™Kœ™[[İ™SØš™Xİ
›Ü’Ù^NˆÙ^JCBˆCBˆ›Üˆ
Ù^K]JH[ˆ˜[œØXİ[Û‹\™Ù]Ù][™ÜĞ™Y›Ü™U˜[œÚ][ÛˆÃBˆİX\™]˜[YHHOÈ›Ü\S\İÙ\šX[^˜][Û‹œ›Ü\S\İ
Bˆœ›ÛNˆ]KBˆÜ[ÛœÎˆ×KBˆ›Ü›X]ˆš[Bˆ
H[ÙHÈÛÛ[YHCBˆİÜ™KœÙ]
˜[YK›Ü’Ù^NˆÙ^JCBˆCBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™\İÜ™TÚ\™TÙ\šXÙ\Ó[ÙPY\‘˜Z[Y™\İÜ™JBˆÈ˜[œØXİ[ÛˆÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛƒBˆ
H\Ş[˜ÈÃBˆYˆ˜[œØXİ[Û‹™YİÚ]ÚÃBˆ›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÈH˜[œØXİ[Û‹œ™]š[İ\Õ˜[YCBˆÙ\šXÙTİÜ™TØÛÜK˜Xİ]™T›Ùš[QYÚ[™ÙJ›İYSØœÙ\™\œÎˆ˜[ÙJCBˆH[ÙHÃBˆÙ\šXÙTİÜ™TØÛÜKÚ[Ú[™ÙPXİ]™T›Ùš[J
CBˆCBˆYˆ]Û˜\ÚİH˜[œØXİ[Û‹\™Ù]İÜ™TÛ˜\ÚİÃBˆÈÃBˆHÙ\šXÙTİÜ™TØÛÜKœ™\İÜ™TİÜ™Qš[TÛ˜\Úİ
Û˜\Úİ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ˜Z[YÈ™\İÜ™HH™KX][\Ù\šXÙ\È]X˜\ÙNˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBˆÙ\šXÙTİÜ™TØÛÜK™\ØØ\™İÜ™Qš[TÛ˜\Úİ
Û˜\Úİ
CBˆCBˆ™\İÜ™TÙ\šXÙ\ÔÙ][™ÜĞY\‘˜Z[Y˜[œÚ][ÛŠ˜[œØXİ[ÛŠCBˆÈH]ØZ]™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[Š
KBˆÛ\˜]\Ò[™\™XY\”[[YNˆYCBˆ
CBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™\İÜ™YÚ\™HÙ\šXÙ\È[ÙH[™ØÛÜYÛİ\˜ÙHİ]HY\ˆH˜Z[Y™\İÜ™H‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBƒBˆš]˜]H[˜ÈÛÛ\]TÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛŠBˆÈ˜[œØXİ[ÛˆÚ\™TÙ\šXÙ\Ô™\İÜ™U˜[œØXİ[ÛƒBˆ
HÃBˆYˆ]Û˜\ÚİH˜[œØXİ[Û‹\™Ù]İÜ™TÛ˜\ÚİÃBˆÙ\šXÙTİÜ™TØÛÜK™\ØØ\™İÜ™Qš[TÛ˜\Úİ
Û˜\Úİ
CBˆCBˆCBƒBˆXZ[XİÜƒBˆ[˜È™\\™T™XY\‘^[œÚ[Û]][XØ][Û‘›ÜXØÛİ[›İ[™\JBˆİ]ÛÚ[™Ô›Ùš[RQÎˆÙ]URQƒBˆ
HOˆ›ÛÛÃBˆÚYˆÜÊSÔÊCBˆÈÃBˆ]™\İ[HH™XY\‘^[œÚ[Û”›Ùš[P]][XØ][Û“Y™XŞXÛCBˆœ™\\™Q›Ü”›Ùš[TİÜ™Q[][ÛŠBˆ›Ùš[RQÎˆ\œ˜^Jİ]ÛÚ[™Ô›Ùš[RQÊCBˆ
CBˆYˆ]\œ›ÜˆH™\İ[™š\œİ\œ›ÜˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™XY\ˆ]][XØ][ÛˆÛX[\™[XZ[œÈ\˜X›H[™[™È]HXØÛİ[›İ[™\Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™Y\ÙYÈÛX\ˆ™XY\ˆY]Y]H™XØ]\ÙH]][XØ][ÛˆÛX[\Ûİ[›İ™HÚXÚÜÚ[Yˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[ÙCBˆÈHİ]ÛÚ[™Ô›Ùš[RQÃBˆÙ[™YƒBˆ™]\›ˆYCBˆCBƒBˆXZ[XİÜƒBˆ[˜È™\XÙPXİ]™TÛİ\˜Ù\ÕÚ]XØÛİ[™]]˜[İ]JBˆİ]ÛÚ[™Ô›Ùš[RQÎˆÙ]URQ‹Bˆ™XY\]][XØ][ÛÛX[\™\\™Yˆ›ÛÛH˜[ÙCBˆ
HOˆ›ÛÛÃBˆYˆ\™XY\]][XØ][ÛÛX[\™\\™YBˆ\™\\™T™XY\‘^[œÚ[Û]][XØ][Û‘›ÜXØÛİ[›İ[™\JBˆİ]ÛÚ[™Ô›Ùš[RQÎˆİ]ÛÚ[™Ô›Ùš[RQÃBˆ
HÃBˆ™]\›ˆ˜[ÙCBˆCBˆ]Ù\šXÙTİÜ™HHÙ\šXÙTİÜ™KœÚ\™YBˆ”Ù\šXÙTÙ][™Õ˜][œ™[[İ™P[XØÛİ[Ñ›ÜXØÛİ[›İ[™\J
CBˆİ™[Z[ĞÛÛ™šYİ\™YT“˜][œ™[[İ™P[XØÛİ[Ñ›ÜXØÛİ[›İ[™\J
CBƒBˆ]ÛX\™YÙ\šXÙ\ÈHÙ\šXÙTİÜ™Kœ™[[İ™P[Ù\šXÙ\Ñ›ÜXØÛİ[›İ[™\J
CBˆ]ÛX\™YYÛœÈHİ™[Z[ĞYÛ”İÜ™KœÚ\™Yœ™[[İ™P[

CBˆ]ÛX\™YÚŞTİ™X[HHÙ\šXÙTİÜ™K˜ÛX\”ÚŞTİ™X[Tİ]Q]Q›ÜXØÛİ[›İ[™\J
CBƒBˆ]Y˜][ÈH›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ÃBˆÚYˆ[ÜÊ“ÔÊCBˆ]™]Z[™YÙ\šXÙ\ÒÙ^\ÎˆÙ]İš[™ÏˆHÃBˆ™XY\‘^[œÚ[Û”\œÚ\İ[˜ÙKœ[™[™Ğ]][XØ][ÛÛX[\Ù^CBˆCBˆÙ[ÙCBˆ]™]Z[™YÙ\šXÙ\ÒÙ^\ÎˆÙ]İš[™ÏˆH×CBˆÙ[™YƒBˆ›ÜˆÙ^H[ˆY˜][Ë™Xİ[Û˜\T™\™\Ù[][ÛŠ
KšÙ^\ÃBˆÚ\™HXÛ\ÙTÙ][™ÜÔ™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHœÙ\šXÙ\ÃBˆ	‰ˆ\™]Z[™YÙ\šXÙ\ÒÙ^\Ë˜ÛÛZ[œÊÙ^JHÃBˆY˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^NˆÙ^JCBˆCBƒBˆÚYˆÜÊSÔÊCBˆ]ÛX\™Y[Ù[\ÈH[Ù[SX[˜YÙ\‹œÚ\™Yœ™\XÙUÚ]XØÛİ[™]]˜[Y]Y]J
CBˆÈÃBˆH˜XÚİ\™XY\‘^[œÚ[Û”İ]JBˆY]Y]R”ÓÓˆš[Bˆ[œİ[YÛİ\˜ÙPÛİ[ˆBˆÚİÓX]\™TÛİ\˜Ù\Îˆ˜[ÙKBˆ]]Õ\]TÛİ\˜Ù\ÎˆYKBˆ\İ]]Õ\]Nˆš[Bˆ
Kœ™\İÜ™JÎˆY˜][ÊCBˆY˜][Ëœ™[[İ™SØš™Xİ
Bˆ›Ü’Ù^Nˆ˜XÚİ\™XY\‘^[œÚ[Û”İ]K›YØXŞPZYÚİTÛİ\˜Ù\ÔİÜ˜YÙRÙ^CBˆ
CBˆHØ]ÚÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÛİ[›İÛX\ˆ™XY\ˆ^[œÚ[ÛˆY]Y]H]HXØÛİ[›İ[™\H‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙ[ÙCBˆ]ÛX\™Y[Ù[\ÈHYCBˆÙ[™YƒBƒBˆÙ\šXÙSX[˜YÙ\‹œÚ\™Y›ØYÙ\šXÙ\Ñœ›ÛPÛİY

CBˆİ™[Z[ĞYÛ“X[˜YÙ\‹œÚ\™Y›ØYYÛœÊ
CBˆÛİ\˜ÙRX[İÜ™KœÚ\™Yœ™[ØY\œÚ\İYİ]PY\”™\İÜ™J
CBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆ]š[ÔYÚ[“X[˜YÙ\‹œÚ\™Y›ØY

CBˆÙ[™YƒBƒBˆ™]\›ˆÛX\™YÙ\šXÙ\È	‰ˆÛX\™YYÛœÈ	‰ˆÛX\™YÚŞTİ™X[H	‰ˆÛX\™Y[Ù[\ÃBˆCBƒBˆXZ[XİÜƒBˆ[˜È™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\XØÛİ[›İ[™\J
H\Ş[˜ÈOˆ›ÛÛÃBˆ]ØZ]™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[Š
KBˆÛ\˜]\Ò[™\™XY\”[[YNˆYCBˆ
CBˆCBƒBˆXZ[XİÜƒBˆš]˜]H[˜È™[ØYÛİ\˜ÙSX[˜YÙ\œĞY\”™\İÜ™JBˆ^XİYØÛÜNˆXİ]™T›Ùš[TØÛÜUÚÙ[‹BˆÛ\˜]\Ò[™\™XY\”[[YNˆ›ÛÛH˜[ÙCBˆ
H\Ş[˜ÈOˆ›ÛÛÃBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBƒBˆÙ\šXÙSX[˜YÙ\‹œÚ\™Y›ØYÙ\šXÙ\Ñœ›ÛPÛİY

CBˆİ™[Z[ĞYÛ“X[˜YÙ\‹œÚ\™Y›ØYYÛœÊ
CBˆÛİ\˜ÙRX[İÜ™KœÚ\™Yœ™[ØY\œÚ\İYİ]PY\”™\İÜ™J
CBƒBˆ]ØZ]ÚŞTİ™X[TYÚ[“X[˜YÙ\‹œÚ\™Yœ™[ØY\œÚ\İYİ]PY\”™\İÜ™J
CBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠKBˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][Ûˆ[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBƒBˆÚYˆÜÊSÔÊH	‰ˆ]\™Ù][š\›Û›Y[
XXĞØ][\İ
CBˆYˆ]›Ü›PØ\Xš[]Y\Ë˜İ\œ™[œİ\ÜÓ]š[ÔYÚ[œÈÃBˆİX\™]ØZ]]š[ÔYÚ[“X[˜YÙ\‹œÚ\™Yœ™[ØY\œÚ\İYİ]PY\”™\İÜ™JBˆ^XİYØÛÜQÙ[™\˜][Ûˆ^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛƒBˆ
H[ÙHÈ™]\›ˆ˜[ÙHCBˆCBˆÙ[™YƒBˆÚYˆ[ÜÊ“ÔÊCBˆÈÃBˆİX\™H™XY\‘^[œÚ[Û“X[˜YÙ\‹œÚ\™Yœ™[ØY\œÚ\İYİ]PY\”™\İÜ™J
H[ÙHÃBˆ™]\›ˆ˜[ÙCBˆCBˆHØ]ÚÃBˆİX\™Û\˜]\Ò[™\™XY\”[[YKBˆ™XY\‘^[œÚ[Û”™\İÜ™T™[ØYÛXŞKœ™\İÜ™Tİ\š]™\Ê\œ›ÜŠH[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™XY\ˆ^[œÚ[ÛˆY]Y]HÛİ[›İ™[ØYY\ˆ™\İÜ™Nˆ
\œ›Ü‹›ØØ[^™Y\ØÜš\[ÛŠH‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆ™]\›ˆ˜[ÙCBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™XY\ˆ^[œÚ[ÛœÈİ^YY[™\Y\ˆ™\İÜ™NÈ]™\Hİ\ˆ™\İÜ™YÛXZ[ˆİ[™È‹Bˆ\Nˆ”İÜ˜YÙHƒBˆ
CBˆCBˆÙ[™YƒBƒBˆ™]\›ˆ›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQOH^XİYØÛÜKœ›Ùš[RQBˆ	‰ˆÙ\šXÙTİÜ™TØÛÜKš\Ğİ\œ™[
^XİYØÛÜKœÙ\šXÙ\ÑÙ[™\˜][ÛŠCBˆ	‰ˆ›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\‘Ù[™\˜][ÛˆOH^XİYØÛÜKœ›Üİ\‘Ù[™\˜][ÛƒBˆCBƒBˆš]˜]H[˜È\P˜XÚİ\]JBˆÈ˜XÚİ\ˆ˜XÚİ\]KBˆ™Yœ™\ÚÛİYÛİ\˜Ù\Îˆ›ÛÛH˜[ÙKBˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]Nˆ›ÛÛH˜[ÙKBˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[Ûˆ›ÛÛH˜[ÙCBˆ
HOˆ˜XÚİ\\XØ][Û”™\İ[ÈÃBˆ˜\ˆ˜XÚÙ\“X[˜YÙ\ˆ˜XÚÙ\“X[˜YÙ\ˆCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ˜XÚÙ\“X[˜YÙ\ˆH˜XÚÙ\“X[˜YÙ\‹œÚ\™YBˆCBˆ˜XÚÙ\“X[˜YÙ\‹œÙ]˜XÚİ\™\İÜ™TŞ[˜Ôİ\™\ÜÙY
YJCBˆY™\ˆÃBˆ˜XÚÙ\“X[˜YÙ\‹œÙ]˜XÚİ\™\İÜ™TŞ[˜Ôİ\™\ÜÙY
˜[ÙJCBˆCBƒBˆ]Ü]™[İÛ™\ˆH˜XÚİ\˜Xİ]™T›Ùš[RQBƒBˆ]Xİ]™T›Ùš[RQHİ\œ™[Xİ]™T›Ùš[RQ

CBˆ˜\ˆ\Y\ÕÜ]™[\”›Ùš[Q]HHİ\œ™[›Ùš[T›Üİ\’\Ô™XYX›J
CBˆ	‰ˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]CBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ]Ü]™[İÛ™\ˆÃBˆ\Y\ÕÜ]™[\”›Ùš[Q]HHÜ]™[İÛ™\ˆOHXİ]™T›Ùš[RQBˆCBˆYˆX\Y\ÕÜ]™[\”›Ùš[Q]HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆHÜ[]™[^[ØY™[Û™ÜÈÈ›Ùš[H
Ü]™[İÛ™\Ë]ZYİš[™ÈÏÈÈŠKÚXÚ\È›İXİ]™H\™NÈ]Ú[™H™\İÜ™Yœ›ÛHH\‹\›Ùš[H›Üİ\ˆ[œİXY‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆCBƒBˆ]Ü]™[Û˜\ÚİHÜ]™[İÛ™\‹™›]X\ÈİÛ™\ˆ[ƒBˆ˜XÚİ\œ›Ùš[\ÏË™š\œİÈ	šYOHİÛ™\ˆCBˆCBˆ]\Y\ÕÜ]™[ÛÛXİ[ÛœÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆÙ[‹Ü]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ˜XÚİ\š\ĞÛÛXİ[ÛœËBˆ›Ùš[PØ\\™Q›YÎˆÜ]™[Û˜\ÚİË˜ÛÛXİ[ÛœÕÙ\™PØ\\™YBˆ
CBˆ]\Y\ÕÜ]™[›ÙÜ™\ÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆÙ[‹Ü]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ˜XÚİ\š\Ô›ÙÜ™\ÜÑ]KBˆ›Ùš[PØ\\™Q›YÎˆÜ]™[Û˜\ÚİËœ›ÙÜ™\ÜÕØ\ĞØ\\™YBˆ
CBˆ]\Y\ÕÜ]™[˜][™ÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆÙ[‹Ü]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ˜XÚİ\š\Õ\Ù\”˜][™ÜËBˆ›Ùš[PØ\\™Q›YÎˆÜ]™[Û˜\ÚİËœ˜][™ÜÕÙ\™PØ\\™YBˆ
CBˆ]\Y\ÕÜ]™[Ø][ÙÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆÙ[‹Ü]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ˜XÚİ\š\ĞØ][ÙÜËBˆ›Ùš[PØ\\™Q›YÎˆÜ]™[Û˜\ÚİË˜Ø][ÙÜÕÙ\™PØ\\™YBˆ
CBˆ]\Y\ÕÜ]™[˜XÚÙ\ˆH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆÙ[‹Ü]™[ÛXZ[’\Ğ]]Üš]]]™JBˆ^[ØYØ\ÑXÛÙYˆ˜XÚİ\š\Õ˜XÚÙ\”İ]KBˆ›Ùš[PØ\\™Q›YÎˆÜ]™[Û˜\ÚİË˜XÚÙ\”İ]UØ\ĞØ\\™YBˆ
CBˆ]\Y\ÕÜ]™[X[™ØPÛÛXİ[ÛœÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆ
Ü]™[Û˜\ÚİË›X[™ØPÛÛXİ[ÛœÕÙ\™PØ\\™YÏÈYJCBˆ]\Y\ÕÜ]™[X[™ØT›ÙÜ™\ÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆ
Ü]™[Û˜\ÚİË›X[™ØT™XY[™Ô›ÙÜ™\ÜÕØ\ĞØ\\™YÏÈYJCBˆ]\Y\ÕÜ]™[X[™ØPØ][ÙÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆ
Ü]™[Û˜\ÚİË›X[™ØPØ][ÙÜÕÙ\™PØ\\™YÏÈYJCBˆ]\Y\ÕÜ]™[İ\İÛPØ][ÙÜÈH\Y\ÕÜ]™[\”›Ùš[Q]CBˆ	‰ˆ
Ü]™[Û˜\ÚİË˜İ\İÛPØ][ÙÜÕÙ\™PØ\\™YÏÈYJCBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆX\Y\ÕÜ]™[ÛÛXİ[ÛœÈX\Y\ÕÜ]™[›ÙÜ™\ÜÈX\Y\ÕÜ]™[˜][™ÜÃBˆX\Y\ÕÜ]™[Ø][ÙÜÈX\Y\ÕÜ]™[˜XÚÙ\ˆÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆHÜ[]™[^[ØY\ÈZ\ÜÚ[™ÈÛXZ[œÈ]ÈİÛˆ›Ùš[HÛİ[›İØ\\™H
ÛÛXİ[ÛœÏW
\Y\ÕÜ]™[ÛÛXİ[ÛœÊH›ÙÜ™\ÜÏW
\Y\ÕÜ]™[›ÙÜ™\ÜÊH˜][™ÜÏW
\Y\ÕÜ]™[˜][™ÜÊHØ][ÙÜÏW
\Y\ÕÜ]™[Ø][ÙÜÊH˜XÚÙ\W
\Y\ÕÜ]™[˜XÚÙ\ŠJNÈ\È]šXÙHÙY\È]ÈİÛˆÛÜHÙˆÜÙH‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBƒBˆ]\Y\ÕÜ]™[Ûİ\˜Ù\ÈH\Y\ÕÜ]™[Ûİ\˜ÙQ]J˜XÚİ\Xİ]™T›Ùš[RQˆXİ]™T›Ùš[RQ
CBˆYˆX\Y\ÕÜ]™[Ûİ\˜Ù\ÈÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆHÜ[]™[Ûİ\˜Ù\È™[Û™ÈÈ›Ùš[H
Ü]™[İÛ™\Ë]ZYİš[™ÈÏÈÈŠH[™Ù\šXÙ\È\™H›İÚ\™YÈ\È›Ùš[HÙY\È]ÈİÛˆÛİ\˜Ù\È‹Bˆ\Nˆ”Ù\šXÙ\ÈƒBˆ
CBˆCBƒBˆ]\Ù\‘Y˜][ÈHØÛÜYÙ][™ÜÑY˜][ÊBˆ\Y\Ô›Ùš[TØÛÜYÜš]\Îˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ\Y\ÔÙ\šXÙ\ÔØÛÜYÜš]\Îˆ\Y\ÕÜ]™[Ûİ\˜Ù\ËBˆXÛÙYÜ]™[Ù][™ÒÙ^\Îˆ˜XÚİ\™XÛÙYÜ]™[Ù][™ÒÙ^\ËBˆ[Ü]™[Ù][™ÜÕÙ\™PØ\\™Yˆ˜XÚİ\˜[Ü]™[Ù][™ÜÕÙ\™PØ\\™YBˆ
CBƒBˆ]™\Ù\™\ÓØØ[ÚŞTÛİ\˜ÙTÙ][™ÜÈH˜XÚİ\œÚŞTİ™X[HOHš[Bˆ˜XÚİ\œÚŞTİ™X[OËš\ÔØY™PÛİYÛ˜\ÚİOHYCBƒBˆ]™\Ù\™\ÓØØ[]š[ÔÛİ\˜ÙTÙ][™ÜÈH˜XÚİ\›]š[ÔYÚ[œÈOHš[Bˆ]İ\œ™[]]Ó[ÙTÛİ\˜ÙRYÈH\Ù\‘Y˜][Ëœİš[™Ğ\œ˜^JBˆ›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈƒBˆ
HÏÈ×CBˆ]İ\œ™[]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈH\Ù\‘Y˜][Ëœİš[™Ğ\œ˜^JBˆ›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈƒBˆ
HÏÈ×CBˆ]İ\œ™[^˜T[\ÔÛİ\˜ÙRYÈHİ™X[S[™İXYÙQš[\‹™^˜T[\ÔÛİ\˜ÙRYÊ
CBˆ˜\ˆ™\Ù\™YØØ[Ûİ\˜ÙRQÈHÙ]İš[™ÏŠ
CBˆYˆ™\Ù\™\ÓØØ[ÚŞTÛİ\˜ÙTÙ][™ÜÈÃBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠİ\œ™[]]Ó[ÙTÛİ\˜ÙRYË™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[YÚŞTİ™X[TÛİ\˜ÙRQBˆ
JCBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠİ\œ™[]]Ó[ÙTÛİ\˜ÙSÜ™\’YË™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[YÚŞTİ™X[TÛİ\˜ÙRQBˆ
JCBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠ
İ\œ™[^˜T[\ÔÛİ\˜ÙRYÈÏÈ×JK™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[YÚŞTİ™X[TÛİ\˜ÙRQBˆ
JCBˆCBˆYˆ™\Ù\™\ÓØØ[]š[ÔÛİ\˜ÙTÙ][™ÜÈÃBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠİ\œ™[]]Ó[ÙTÛİ\˜ÙRYË™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[Y]š[ÔÛİ\˜ÙRQBˆ
JCBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠİ\œ™[]]Ó[ÙTÛİ\˜ÙSÜ™\’YË™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[Y]š[ÔÛİ\˜ÙRQBˆ
JCBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠ
İ\œ™[^˜T[\ÔÛİ\˜ÙRYÈÏÈ×JK™š[\ŠBˆİ™X[S[™İXYÙQš[\‹š\Õ˜[Y]š[ÔÛİ\˜ÙRQBˆ
JCBˆCBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ËBˆ\Y\ÕÜ]™[Ûİ\˜Ù\ËBˆ][˜ÛÛZ[™Ó]š[Ôİ]HH˜XÚİ\›]š[ÔYÚ[œÈÃBˆ]İ\œ™[]š[Ôİ]HH]š[ÔYÚ[”İÜ™JBˆY˜][Îˆ›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ÃBˆ
K›ØY

CBˆ™\Ù\™YØØ[Ûİ\˜ÙRQË™›Ü›U[š[ÛŠBˆ˜XÚİ\]K›]š[Ô™\İÜ™T[‘›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆ[˜ÛÛZ[™Îˆ[˜ÛÛZ[™Ó]š[Ôİ]KBˆİ\œ™[ˆİ\œ™[]š[Ôİ]CBˆ
K™]šXÙSØØ[Ûİ\˜ÙRQÃBˆ
CBˆCBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ›ÜˆÙ\šXÙH[ˆÙ\šXÙTİÜ™KœÚ\™Y™Ù]Ù\šXÙ\Ê
HÃBˆ]Y]Y]HH
OÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJÙ\šXÙK›Y]Y]JJCBˆ™›]X\Èİš[™Ê]Nˆ	[˜ÛÙ[™Îˆ]
HHÏÈˆƒBˆ]˜XÚİ\Ù\šXÙHH˜XÚİ\Ù\šXÙJBˆYˆÙ\šXÙKšYBˆ\›ˆÙ\šXÙK\›BˆœÛÛ“Y]Y]NˆY]Y]KBˆœÔØÜš\ˆÙ\šXÙKšœÔØÜš\Bˆ\ĞXİ]™NˆÙ\šXÙKš\ĞXİ]™KBˆÛÜ[™^ˆÙ\šXÙKœÛÜ[™^Bˆ
CBˆYˆ˜XÚİ\]KœÙ\šXÙQ›Ü‘^\š[Y[[ÛİYŞ[˜Ê˜XÚİ\Ù\šXÙJHOHš[ÃBˆ™\Ù\™YØØ[Ûİ\˜ÙRQËš[œÙ\
œÙ\šXÙN—
Ù\šXÙKšY]ZYİš[™ÊHŠCBˆCBˆCBˆ›ÜˆYÛˆ[ˆİ™[Z[ĞYÛ”İÜ™KœÚ\™Y™Ù]YÛœÊ
HÃBˆ]X[šY™\İ”ÓÓˆH
OÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJYÛ‹›X[šY™\İ
JCBˆ™›]X\Èİš[™Ê]Nˆ	[˜ÛÙ[™Îˆ]
HHÏÈˆƒBˆ]˜XÚİ\YÛˆH˜XÚİ\İ™[Z[ĞYÛŠBˆYˆYÛ‹šYBˆÛÛ™šYİ\™YT“ˆYÛ‹˜ÛÛ™šYİ\™YT“BˆX[šY™\İ”ÓÓˆX[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™NˆYÛ‹š\ĞXİ]™KBˆÛÜ[™^ˆYÛ‹œÛÜ[™^Bˆ
CBˆYˆ˜XÚİ\]Kœİ™[Z[ĞYÛ‘›Ü‘^\š[Y[[ÛİYŞ[˜Ê˜XÚİ\YÛŠHOHš[ÃBˆ™\Ù\™YØØ[Ûİ\˜ÙRQËš[œÙ\
œİ™[Z[Î—
YÛ‹šY]ZYİš[™ÊHŠCBˆCBˆCBˆCBˆ]™\Ù\™Y^˜T[\ÓØØ[Ûİ\˜ÙRYÈH
İ\œ™[^˜T[\ÔÛİ\˜ÙRYÃBˆÏÈİ\œ™[]]Ó[ÙTÛİ\˜ÙSÜ™\’YÊK™š[\Š™\Ù\™YØØ[Ûİ\˜ÙRQË˜ÛÛZ[œÊCBƒBˆYˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]HÃBˆ˜XÚİ\]Kœ™\İÜ™SYYXTİ]TÙ][™ÜÊBˆ˜XÚİ\›YYXTİ]TÙ][™ÜËBˆ\Y\Ô›Ùš[TØÛÜYÜš]\Îˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ\Y\ÔÙ\šXÙ\ÔØÛÜYÜš]\Îˆ\Y\ÕÜ]™[Ûİ\˜Ù\ÃBˆ
CBˆCBƒBˆYˆ]XØÙ[ÛÛÜ‘]HH˜XÚİ\˜XØÙ[ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
XØÙ[ÛÛÜ‘]K›Ü’Ù^Nˆ˜XØÙ[ÛÛÜˆŠCBˆCBˆYˆ]Ù][™ÜÑÜ˜YY[ÛÛÜˆH˜XÚİ\œÙ][™ÜÑÜ˜YY[ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
Ù][™ÜÑÜ˜YY[ÛÛÜ‹›Ü’Ù^Nˆ™XÛ\ÙU[YQÜ˜YY[ÛÛÜˆŠCBˆCBˆYˆ]™XY\XØÙ[ÛÛÜˆH˜XÚİ\œ™XY\XØÙ[ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
™XY\XØÙ[ÛÛÜ‹›Ü’Ù^Nˆœ™XY\XØÙ[ÛÛÜˆŠCBˆCBˆYˆ]™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆH˜XÚİ\œ™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
™XY\”Ù][™ÜÑÜ˜YY[ÛÛÜ‹›Ü’Ù^Nˆœ™XY\•[YQÜ˜YY[ÛÛÜˆŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\Y“[™İXYÙK›Ü’Ù^NˆY“[™İXYÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJ˜XÚİ\œÙ[XİY\X\˜[˜ÙJK›Ü’Ù^NˆœÙ[XİY\X\˜[˜ÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y\X\˜[˜ÙJ˜XÚİ\œ™XY\”Ù[XİY\X\˜[˜ÙJK›Ü’Ù^Nˆœ™XY\”Ù[XİY\X\˜[˜ÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›Y›Ü’Ù^Nˆœ™XY\‘ÛØ˜[\X\˜[˜ÙQ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™[˜X›TİX]\ĞQY˜][›Ü’Ù^Nˆ™[˜X›TİX]\ĞQY˜][ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Y˜][İX]S[™İXYÙK›Ü’Ù^Nˆ™Y˜][İX]S[™İXYÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\”İX]P\X\˜[˜ÙQ[˜X›Y›Ü’Ù^Nˆœ^Y\”İX]P\X\˜[˜ÙQ[˜X›YŠCBƒBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙK›Ü’Ù^Nˆœ™Y™\œ™Y]]Ğ]Y[Ó[™İXYÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙK›Ü’Ù^Nˆœ™Y™\œ™Y[š[YP]Y[Ó[™İXYÙHŠCBˆ]™\İÜ™Y[™Ú[™T˜]ÈHÙ][™ÜË››Ü›X[^™Y[\^Y\Š˜XÚİ\š[\^Y\ŠCBˆ]XÛÙY[™Ú[™HH^X˜XÚÑ[™Ú[™J˜]Õ˜[YNˆ™\İÜ™Y[™Ú[™T˜]ÊCBˆÏÈ^X˜XÚÑ[™Ú[™K™Y˜][Ù[Xİ[ÛŠ]šXÙQ˜[Z[Nˆ˜İ\œ™[
CBˆ]™\İÜ™Y[™Ú[™HH^X˜XÚÑ[™Ú[™Kœİ\ÜYÙ[Xİ[ÛŠBˆXÛÙY[™Ú[™KBˆ]šXÙQ˜[Z[Nˆ˜İ\œ™[Bˆ
CBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™Y[™Ú[™Kœ˜]Õ˜[YK›Ü’Ù^Nˆ^X˜XÚÑ[™Ú[™K™Y˜][ÒÙ^JCBƒBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™Y[™Ú[™Kœ˜]Õ˜[YK›Ü’Ù^Nˆš[\^Y\ˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÔØÚY[UX‹›Ü’Ù^NˆœÚİÔØÚY[UXˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÓØØ[ØÚY[U[YK›Ü’Ù^NˆœÚİÓØØ[ØÚY[U[YHŠCBˆ\Ù\‘Y˜][ËœÙ]
ØÚY[S[ÙKœØ[š]^™Y˜]Õ˜[YJ˜XÚİ\™Y˜][ØÚY[S[ÙJK›Ü’Ù^Nˆ™Y˜][ØÚY[S[ÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
ØÚY[UÚ[™İËœØ[š]^™Y^\Ê˜XÚİ\œØÚY[UÚ[™İÑ^\ÊK›Ü’Ù^NˆØÚY[UÚ[™İËœİÜ˜YÙRÙ^JCBˆYˆ]˜[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”İXœØÜš\[ÛœÊBˆ˜XÚİ\›ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÃBˆ
HÃBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û”İXœØÜš\[ÛœÈŠCBˆCBˆYˆ]˜[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÊBˆ˜XÚİ\›ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÃBˆ
HÃBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û‘\\ÛÙT™[Z[™\œÈŠCBˆCBˆYˆ]˜[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û‘\\ÛÙSXY[YJBˆ˜XÚİ\›ØØ[›İYšXØ][Û‘\\ÛÙSXY[YCBˆ
HÃBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û‘\\ÛÙSXY[YHŠCBˆCBˆYˆ]˜[YHH˜XÚİ\]KœØ[š]^™YØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YJBˆ˜XÚİ\›ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YCBˆ
HÃBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û”ÙX\ÛÛ“XY[YHŠCBˆCBˆYˆ]˜[YHH˜XÚİ\›ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÈÃBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ›ØØ[›İYšXØ][Û’[˜ÛYP[š[YTÜXÚX[ÈŠCBˆCBƒBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YY˜][^X˜XÚÔÜYY
˜XÚİ\™Y˜][^X˜XÚÔÜYY
KBˆ›Ü’Ù^Nˆ™Y˜][^X˜XÚÔÜYYƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YÛÜYY^Y\Š˜XÚİ\šÛÜYY^Y\ŠKBˆ›Ü’Ù^NˆšÛÜYY^Y\ˆƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\›˜[^Y\‹›Ü’Ù^Nˆ™^\›˜[^Y\ˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™Y™\‘İÛ›ØYYYYXK›Ü’Ù^Nˆœ™Y™\‘İÛ›ØYYYYXHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜[Ø^\Ó[™ØØ\K›Ü’Ù^Nˆ˜[Ø^\Ó[™ØØ\HŠCBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^Nˆ^Y\”^X˜XÚÓØÚÔÙ][™ÜË™[˜X›YÙ^CBˆ
HÃBˆ^Y\”^X˜XÚÓØÚÔÙ][™ÜËœÙ][˜X›Y
˜XÚİ\œ^Y\”^X˜XÚÓØÚÑ[˜X›Y
CBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜[šTÚÚ\[˜X›Y›Ü’Ù^Nˆ˜[šTÚÚ\[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\š[›Ñ‘[˜X›Y›Ü’Ù^Nˆš[›Ñ‘[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\š[›Ñ\[˜X›Y›Ü’Ù^Nˆš[›Ñ\[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜[šTÚÚ\]]ÔÚÚ\›Ü’Ù^Nˆ˜[šTÚÚ\]]ÔÚÚ\ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚÚ\\Ñ[˜X›Y›Ü’Ù^NˆœÚÚ\\Ñ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚÚ\\Ğ[Ø^\Õš\ÚX›K›Ü’Ù^NˆœÚÚ\\Ğ[Ø^\Õš\ÚX›HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÓ™^\\ÛÙP]Û‹›Ü’Ù^NˆœÚİÓ™^\\ÛÙP]ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÑ\\ÛÙPœ›İÜÙ\]Û‹›Ü’Ù^NˆœÚİÑ\\ÛÙPœ›İÜÙ\]ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÔ^Y\”Ù\šXÙ\Ğ]Û‹›Ü’Ù^Nˆ^Y\”Ù\šXÙ\Ğ]Û”Ù][™ÜËšÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÓ™^\\ÛÙTÜİ\]Û‹›Ü’Ù^NˆœÚİÓ™^\\ÛÙTÜİ\]ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y™^\\ÛÙU™\ÚÛ
˜XÚİ\›™^\\ÛÙU™\ÚÛ
KBˆ›Ü’Ù^Nˆ›™^\\ÛÙU™\ÚÛƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›™^\\ÛÙTÚÚ\š[\‘[˜X›Y›Ü’Ù^Nˆ™^\\ÛÙQš[\”Ù][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›Y›Ü’Ù^Nˆœ^Y\œšYÚ™\ÜÑÙ\İ\™Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\•›Û[YQÙ\İ\™Q[˜X›Y›Ü’Ù^Nˆœ^Y\•›Û[YQÙ\İ\™Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›Y›Ü’Ù^Nˆœ^Y\•ÛÑš[™Ù\•\^T]\ÙQ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\Ù[\•\^T]\ÙQ[˜X›Y›Ü’Ù^Nˆœ^Y\Ù[\•\^T]\ÙQ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\‘İX›U\ÙYZÑ[˜X›Y›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÑ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y^Y\‘İX›U\ÙYZÔÙXÛÛ™ÊBˆ˜XÚİ\œ^Y\‘İX›U\ÙYZÔÙXÛÛ™ÃBˆ
KBˆ›Ü’Ù^Nˆœ^Y\‘İX›U\ÙYZÔÙXÛÛ™ÈƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\“Ü[”İX]\Ñ[˜X›Y›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ñ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›Y›Ü’Ù^Nˆœ^Y\“Ü[”İX]\Ğ]]Ñ˜[˜XÚÑ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›Y›Ü’Ù^Nˆœ^Y\”\™›Ü›X[˜ÙSİ™\›^Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\‘›Ü™YÜ›İ[™”ÈOHŒÈŒˆÌ›Ü’Ù^Nˆ›\‘›Ü™YÜ›İ[™”ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT”™[™\˜XÚÙ[™
˜XÚİ\›\”™[™\˜XÚÙ[™
K›Ü’Ù^Nˆ›\”™[™\˜XÚÙ[™ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT“Y][]X[]T›Ùš[J˜XÚİ\›\“Y][]X[]T›Ùš[JK›Ü’Ù^Nˆ›\“Y][]X[]T›Ùš[HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT•\ØØ[[™Ó[ÙJ˜XÚİ\›\•\ØØ[[™Ó[ÙJK›Ü’Ù^Nˆ›\•\ØØ[[™Ó[ÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\Š˜XÚİ\›\“™]\˜[\ØØ[\ŠK›Ü’Ù^Nˆ›\“™]\˜[\ØØ[\ˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT“™]\˜[\ØØ[\Š˜XÚİ\›\“™]\˜[\ØØ[\•ŠK›Ü’Ù^Nˆ›\“™]\˜[\ØØ[\•ˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YT”^Y\”ÚÚ[Š˜XÚİ\›\”^Y\”ÚÚ[ŠK›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜËœÚÚ[’Ù^JCBˆYˆ]š[X\PÛÛÜˆH˜XÚİ\›\”^Y\”ÚÚ[İ\İÛTš[X\PÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
š[X\PÛÛÜ‹›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTš[X\PÛÛÜ’Ù^JCBˆH[ÙHÃBˆ\Ù\‘Y˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTš[X\PÛÛÜ’Ù^JCBˆCBˆYˆ]ÙXÛÛ™\PÛÛÜˆH˜XÚİ\›\”^Y\”ÚÚ[İ\İÛTÙXÛÛ™\PÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
ÙXÛÛ™\PÛÛÜ‹›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTÙXÛÛ™\PÛÛÜ’Ù^JCBˆH[ÙHÃBˆ\Ù\‘Y˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜İ\İÛTÙXÛÛ™\PÛÛÜ’Ù^JCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\”^Y\”ÚÚ[[š[X][ÛœÑ[˜X›Y›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË˜[š[X][ÛœÑ[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\”^Y\”ÚÚ[•[ÛÛ›ÛÓÛ›K›Ü’Ù^NˆT”^Y\”ÚÚ[”Ù][™ÜË[ÛÛ›ÛÓÛ›RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\”Xİ\™R[”Xİ\™Q[˜X›Y›Ü’Ù^Nˆ›\”Xİ\™R[”Xİ\™Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\\^]Xİ\™R[”Xİ\™Q[˜X›Y›Ü’Ù^Nˆ›\\^]Xİ\™R[”Xİ\™Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
T’“[ÙJ˜]Õ˜[YNˆ˜XÚİ\›\’“[ÙJOËœ˜]Õ˜[YHÏÈT’“[ÙK™Y˜][[ÙKœ˜]Õ˜[YK›Ü’Ù^Nˆ›\’“[ÙHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›\”İ\œ›İ[™Ûİ[™[˜X›Y›Ü’Ù^Nˆ›\”İ\œ›İ[™Ûİ[™[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\Ø]ÚÙÙ]\‘[˜X›Y›Ü’Ù^NˆØ]ÚÙÙ]\”Ù][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›Y›Ü’Ù^NˆœÛX\[\^Y\ÚÛÜÚ[™Ñ[˜X›YŠCBˆYˆ]^\š[Y[[™X]\™\Ñ[˜X›YH˜XÚİ\™^\š[Y[[™X]\™\Ñ[˜X›YÃBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[™X]\™\Ñ[˜X›Y›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y^\š[Y[[™X]\™\Ó\İÚ[™ÙY]
Bˆ˜XÚİ\™^\š[Y[[™X]\™\Ó\İÚ[™ÙY]Bˆ
HÏÈBˆ›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\İÚ[™ÙY]Ù^CBˆ
CBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”™[ØY[˜X›Y›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØY[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”Û[Ûİ˜[œÚ][Û‘[˜X›Y›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”Û[Ûİ˜[œÚ][Û‘[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”™[ØYÙ[[\‘[˜X›Y›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÙ[[\‘[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[™X]\™Tİ]K˜Û[\YT”™[ØYÚYšS[Z]PŠ˜XÚİ\™^\š[Y[[T”™[ØYÚYšS[Z]PŠK›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÚYšS[Z]P’Ù^JCBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[™X]\™Tİ]K˜Û[\YT”™[ØYÙ[[\“[Z]PŠ˜XÚİ\™^\š[Y[[T”™[ØYÙ[[\“[Z]PŠK›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØYÙ[[\“[Z]P’Ù^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”ÚİÔ™[XZ[š[™Õ[YK›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”ÚİÔ™[XZ[š[™Õ[YRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”™XÚ\ÙT›ÙÜ™\ÜË›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™XÚ\ÙT›ÙÜ™\ÜÒÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T’YÛ›Ü™TÜXÚX[İX]Tİ[\Ë›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\’YÛ›Ü™TÜXÚX[İX]Tİ[\ÒÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[T”™[ØY]]ĞÛX\‹›Ü’Ù^Nˆ^\š[Y[[™X]\™Tİ]K›\”™[ØY]]ĞÛX\’Ù^JCBƒBˆYˆ]™ĞÛÛÜˆH˜XÚİ\œİX]Q›Ü™YÜ›İ[™ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
™ĞÛÛÜ‹›Ü’Ù^NˆœİX]\×Ù›Ü™YÜ›İ[™ÛÛÜˆŠCBˆCBˆYˆ]İ›ÚÙPÛÛÜˆH˜XÚİ\œİX]Tİ›ÚÙPÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
İ›ÚÙPÛÛÜ‹›Ü’Ù^NˆœİX]\×Üİ›ÚÙPÛÛÜˆŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YİX]Tİ›ÚÙUÚY
˜XÚİ\œİX]Tİ›ÚÙUÚY
KBˆ›Ü’Ù^NˆœİX]\×Üİ›ÚÙUÚYƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YİX]Q›ÛÚ^™J˜XÚİ\œİX]Q›ÛÚ^™JKBˆ›Ü’Ù^NˆœİX]\×Ù›ÛÚ^™HƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YİX]U™\XØ[Ù™œÙ]
˜XÚİ\œİX]U™\XØ[Ù™œÙ]
KBˆ›Ü’Ù^Nˆœ^Y\”İX]Sİ™\›^P›İÛPÛÛœİ[ƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œİX]\Õš\ÚX›K›Ü’Ù^NˆœİX]\×Ú\Õš\ÚX›HŠCBƒBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÚİÒØ[™[‹›Ü’Ù^NˆœÚİÒØ[™[ˆŠCBˆYˆ]YTÜ\ÚØÜ™Y[ˆH˜XÚİ\šYTÜ\ÚØÜ™Y[ˆÃBˆ\Ù\‘Y˜][ËœÙ]
YTÜ\ÚØÜ™Y[‹›Ü’Ù^NˆšYTÜ\ÚØÜ™Y[ˆŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›[ÙTİÚ]Ú[š[X][Û‘[˜X›Y›Ü’Ù^Nˆ[ÙTİÚ]Ú[š[X][Û”Ù][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\šØ[™[]]Õ\]S[Ù[\Ë›Ü’Ù^NˆšØ[™[]]Õ\]S[Ù[\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÙX\ÛÛ“Y[K›Ü’Ù^NˆœÙX\ÛÛ“Y[HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\šÜš^›Û[\\ÛÙS\İ›Ü’Ù^NˆšÜš^›Û[\\ÛÙS\İŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›YYXQ]Z[]P\ÛÜšÑ[˜X›Y›Ü’Ù^NˆYYXQ]Z[]P\ÛÜšÔÙ][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›YYXQ]Z[[\›˜]TÜİ\‘[˜X›Y›Ü’Ù^NˆYYXQ]Z[[\›˜]TÜİ\”Ù][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›YYXQ]Z[Ú[Z[\•]\Ñ[˜X›Y›Ü’Ù^NˆYYXQ]Z[Ú[Z[\•]\ÔÙ][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\\ÙPÛ\ÜÚXÔØÚY[URK›Ü’Ù^Nˆ\ÙPÛ\ÜÚXÔØÚY[URHŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y›Û‘[\Tİš[™Ê˜XÚİ\š\›Ğ˜[›™\Ø][ÙÒYY˜][˜[YNˆ™[™[™ÈŠK›Ü’Ù^Nˆš\›Ğ˜[›™\Ø][ÙÒYŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y\›Ğ˜[›™\™Z]š[ÜŠ˜XÚİ\š\›Ğ˜[›™\™Z]š[ÜŠK›Ü’Ù^Nˆš\›Ğ˜[›™\™Z]š[ÜˆŠCBˆYˆ]İ™\œšY\Ñ]HH˜XÚİ\šÛYPØ][ÙÓ^[İ]İ™\œšY\Ë™]J\Ú[™Îˆ]
KX˜XÚİ\šÛYPØ][ÙÓ^[İ]İ™\œšY\Ëš\Ñ[\HÃBˆ\Ù\‘Y˜][ËœÙ]
İ™\œšY\Ñ]K›Ü’Ù^NˆÛYPØ][ÙÓ^[İ]İÜ™KœİÜ˜YÙRÙ^JCBˆH[ÙHÃBˆ\Ù\‘Y˜][Ëœ™[[İ™SØš™Xİ
›Ü’Ù^NˆÛYPØ][ÙÓ^[İ]İÜ™KœİÜ˜YÙRÙ^JCBˆCBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]HÃBˆÛYPØ][ÙÓ^[İ]İÜ™KœÚ\™Yœ™[ØYœ›ÛTİÜ˜YÙJ
CBˆCBˆYˆ]ÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YH˜XÚİ\šÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›YÃBˆ\Ù\‘Y˜][ËœÙ]
ÛYP[š[X]Y˜XÚÙÜ›İ[™[˜X›Y›Ü’Ù^NˆÛYP[š[X]Y˜XÚÙÜ›İ[™Ù][™ÜË™[˜X›YÙ^JCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]J˜XÚİ\šÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]JK›Ü’Ù^NˆÛYP[š[X]Y˜XÚÙÜ›İ[™]X[]KœİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]J˜XÚİ\šÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]JK›Ü’Ù^NˆÛYP[š[X]Y˜XÚÙÜ›İ[™œ˜[YT˜]KœİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜\\™›Ü›X[˜ÙSİ™\›^Q[˜X›Y›Ü’Ù^Nˆ\\™›Ü›X[˜ÙSİ™\›^TÙ][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXQ\ÚYÛ”™\Ù]
˜XÚİ\™^\š[Y[[YYXQ\ÚYÛ”™\Ù]
K›Ü’Ù^Nˆ^\š[Y[[YYXQ\ÚYÛ”™\Ù]œİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YY]™[
˜XÚİ\™^\š[Y[[\›Ğ›YY]™[
K›Ü’Ù^Nˆ^\š[Y[[\›Ğ›YY]™[œİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÛYPØ\™Ú\J˜XÚİ\™^\š[Y[[ÛYPØ\™Ú\JK›Ü’Ù^Nˆ^\š[Y[[ÛYPØ\™Ú\KœİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[][QÜ˜YY[[]J˜XÚİ\™^\š[Y[[][QÜ˜YY[[]JK›Ü’Ù^Nˆ^\š[Y[[][QÜ˜YY[[]KœİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›ÒZYÚØØ[J˜XÚİ\™^\š[Y[[\›ÒZYÚØØ[JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›ÒZYÚØØ[RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ğ›YYİ™[™İ
˜XÚİ\™^\š[Y[[\›Ğ›YYİ™[™İ
K›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›Ğ›YYİ™[™İÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[J˜XÚİ\™^\š[Y[[\›Ñ˜YQ\İ[˜ÙTØØ[JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ëš\›Ñ˜YQ\İ[˜ÙTØØ[RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[J˜XÚİ\™^\š[Y[[ÙXİ[Û”ÜXÚ[™ÔØØ[JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™ËœÙXİ[Û”ÜXÚ[™ÔØØ[RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ø\™˜Y]\ÔØØ[J˜XÚİ\™^\š[Y[[Ø\™˜Y]\ÔØØ[JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë˜Ø\™˜Y]\ÔØØ[RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[YYXPØ\™ØØ[J˜XÚİ\™^\š[Y[[YYXPØ\™ØØ[JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë›YYXPØ\™ØØ[RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[Û\ÜÔİ™[™İ
˜XÚİ\™^\š[Y[[Û\ÜÔİ™[™İ
K›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Û\ÜÔİ™[™İÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÊ˜XÚİ\™^\š[Y[[Ü˜YY[˜\ÙQ\šÛ™\ÜÊK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[˜\ÙQ\šÛ™\ÜÒÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[XØÙ[[[œÚ]J˜XÚİ\™^\š[Y[[Ü˜YY[XØÙ[[[œÚ]JK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[XØÙ[[[œÚ]RÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛŠ˜XÚİ\™^\š[Y[[Ü˜YY[ØÜ›Û[İ[ÛŠK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ØÜ›Û[İ[Û’Ù^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™^\š[Y[[Ü˜YY[\ÙPİ\İÛPÛÛÜœË›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[\ÙPİ\İÛPÛÛÜœÒÙ^JCBˆYˆ]^\š[Y[[Ü˜YY[ÛÛÜHH˜XÚİ\™^\š[Y[[Ü˜YY[ÛÛÜHÃBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[Ü˜YY[ÛÛÜK›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜRÙ^JCBˆCBˆYˆ]^\š[Y[[Ü˜YY[ÛÛÜˆH˜XÚİ\™^\š[Y[[Ü˜YY[ÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[Ü˜YY[ÛÛÜ‹›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜ’Ù^JCBˆCBˆYˆ]^\š[Y[[Ü˜YY[ÛÛÜÈH˜XÚİ\™^\š[Y[[Ü˜YY[ÛÛÜÈÃBˆ\Ù\‘Y˜][ËœÙ]
^\š[Y[[Ü˜YY[ÛÛÜË›Ü’Ù^Nˆ^\š[Y[[š\İX[[š[™Ë™Ü˜YY[ÛÛÜÒÙ^JCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[J˜XÚİ\˜][ÜÜ\™Tİ[JK›Ü’Ù^Nˆ˜][ÜÜ\™Tİ[HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJ˜XÚİ\˜][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJK›Ü’Ù^Nˆ˜][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHŠCBˆYˆ]][ÜÜ\™TÛÛYÛÛÜˆH˜XÚİ\˜][ÜÜ\™TÛÛYÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
][ÜÜ\™TÛÛYÛÛÜ‹›Ü’Ù^Nˆ˜][ÜÜ\™TÛÛYÛÛÜˆŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y][ÜÜ\™Tİ[J˜XÚİ\œ™XY\][ÜÜ\™Tİ[JK›Ü’Ù^Nˆœ™XY\][ÜÜ\™Tİ[HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJ˜XÚİ\œ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙJK›Ü’Ù^Nˆœ™XY\][ÜÜ\™TÛÛYÛÛÜ”Ûİ\˜ÙHŠCBˆYˆ]™XY\][ÜÜ\™TÛÛYÛÛÜˆH˜XÚİ\œ™XY\][ÜÜ\™TÛÛYÛÛÜˆÃBˆ\Ù\‘Y˜][ËœÙ]
™XY\][ÜÜ\™TÛÛYÛÛÜ‹›Ü’Ù^Nˆœ™XY\][ÜÜ\™TÛÛYÛÛÜˆŠCBˆCBˆ]™\İÜ™YYYXQ]Z[Y[‘[[Y[ÈH˜XÚİ\]KœØ[š]^™YYYXQ]Z[Y[‘[[Y[Ê˜XÚİ\›YYXQ]Z[Y[‘[[Y[ÊCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YYYXQ]Z[[[Y[Ü™\Š˜XÚİ\›YYXQ]Z[[[Y[Ü™\ŠK›Ü’Ù^NˆYYXQ]Z[[[Y[›Ü™\”İÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™YYYXQ]Z[Y[‘[[Y[Ë›Ü’Ù^NˆYYXQ]Z[[[Y[šY[”İÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
SYYXQ]Z[[[Y[šY[‘[[Y[Êœ›ÛNˆ™\İÜ™YYYXQ]Z[Y[‘[[Y[ËYØXŞTÚİĞØ\İÙXİ[ÛˆYJK˜ÛÛZ[œÊ˜Ø\İ
K›Ü’Ù^NˆYYXQ]Z[[[Y[›YØXŞTÚİĞØ\İİÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\‘]Z[[[Y[Ü™\Š˜XÚİ\œ™XY\‘]Z[[[Y[Ü™\ŠK›Ü’Ù^Nˆ™XY\‘]Z[[[Y[›Ü™\”İÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\‘]Z[Y[‘[[Y[Ê˜XÚİ\œ™XY\‘]Z[Y[‘[[Y[ÊK›Ü’Ù^Nˆ™XY\‘]Z[[[Y[šY[”İÜ˜YÙRÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›YYXPÛÛ[[œÔÜ˜Z]›Ü’Ù^Nˆ›YYXPÛÛ[[œÔÜ˜Z]ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\›YYXPÛÛ[[œÓ[™ØØ\K›Ü’Ù^Nˆ›YYXPÛÛ[[œÓ[™ØØ\HŠCBƒBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY[™Ó[ÙK›Ü’Ù^Nˆœ™XY[™Ó[ÙHŠCBˆ]™\İÜ™YØ[™[”™XY\“[ÙHH˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙJ˜XÚİ\šØ[™[”™XY\“[ÙJCBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™YØ[™[”™XY\“[ÙK›Ü’Ù^NˆšØ[™[”™XY\“[ÙHŠCBˆ˜XÚİ\]KœØ[š]^™YØ[™[”™XY\“[ÙSİ™\œšY\Ê˜XÚİ\šØ[™[”™XY\“[ÙSİ™\œšY\ÊK™›Ü‘XXÚÈÙ^K˜[YH[ƒBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^NˆšØ[™[”™XY\“[ÙK—
Ù^JHŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘İÛœØ[\R[XYÙ\Ë›Ü’Ù^Nˆ”™XY\‹™İÛœØ[\R[XYÙ\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\Ü›Ü›Ü™\œË›Ü’Ù^Nˆ”™XY\‹˜Ü›Ü›Ü™\œÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘\ØX›T]ZXÚĞXİ[ÛœË›Ü’Ù^Nˆ”™XY\‹™\ØX›T]ZXÚĞXİ[ÛœÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘\ØX›QİX›U\›Ü’Ù^Nˆ”™XY\‹™\ØX›QİX›U\ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\“]™U^›Ü’Ù^Nˆ”™XY\‹›]™U^ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\’YP˜\œÓÛ”İÚ\K›Ü’Ù^Nˆ”™XY\‹šYP˜\œÓÛ”İÚ\HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\˜XÚÙÜ›İ[™ÛÛÜŠ˜XÚİ\œ™XY\˜XÚÙÜ›İ[™ÛÛÜŠK›Ü’Ù^Nˆ”™XY\‹˜˜XÚÙÜ›İ[™ÛÛÜˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][ÛŠ˜XÚİ\œ™XY\“ÜšY[][ÛŠK›Ü’Ù^Nˆ”™XY\‹›ÜšY[][ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\•\›Û™\Ê˜XÚİ\œ™XY\•\›Û™\ÊK›Ü’Ù^Nˆ”™XY\‹\›Û™\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\’[™\\›Û™\Ë›Ü’Ù^Nˆ”™XY\‹š[™\\›Û™\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\[š[X]TYÙU˜[œÚ][ÛœË›Ü’Ù^Nˆ”™XY\‹˜[š[X]TYÙU˜[œÚ][ÛœÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\•\ØØ[R[XYÙ\Ë›Ü’Ù^Nˆ”™XY\‹\ØØ[R[XYÙ\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\•\ØØ[SX^ZYÚ
˜XÚİ\œ™XY\•\ØØ[SX^ZYÚ
K›Ü’Ù^Nˆ”™XY\‹\ØØ[SX^ZYÚŠCBˆYˆ]™XY\•\ØØ[S[Ù[˜[YHH˜XÚİ\™XY\•\ØØ[S[Ù[™\İÜ™TÛXŞK›[Ù[˜[YUĞ\JBˆ[˜ÛÛZ[™Îˆ˜XÚİ\œ™XY\•\ØØ[S[Ù[˜[YKBˆ™\Ù\™\Ñ]šXÙSØØ[Ù[Xİ[Ûˆ™\Ù\š[™Ñ]šXÙSØØ[™XY\“[Ù[Ù[Xİ[ÛƒBˆ
HÃBˆ\Ù\‘Y˜][ËœÙ]
™XY\•\ØØ[S[Ù[˜[YK›Ü’Ù^Nˆ”™XY\‹\ØØ[S[Ù[˜[YHŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\”YÙ\ÕÔ™[ØY
˜XÚİ\œ™XY\”YÙ\ÕÔ™[ØY
K›Ü’Ù^Nˆ”™XY\‹œYÙ\ÕÔ™[ØYŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙS^[İ]
˜XÚİ\œ™XY\”YÙYYÙS^[İ]
K›Ü’Ù^Nˆ”™XY\‹œYÙYYÙS^[İ]ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\”YÙYYÙSÙ™œÙ]›Ü’Ù^Nˆ”™XY\‹œYÙYYÙSÙ™œÙ]ŠCBˆ˜XÚİ\]KœØ[š]^™Y™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\Ê˜XÚİ\œ™XY\”YÙYYÙSÙ™œÙ]İ™\œšY\ÊK™›Ü‘XXÚÈÙ^K˜[YH[ƒBˆ\Ù\‘Y˜][ËœÙ]
˜[YK›Ü’Ù^Nˆ”™XY\‹œYÙYYÙSÙ™œÙ]—
Ù^JHŠCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\”Ü]ÚYR[XYÙ\Ë›Ü’Ù^Nˆ”™XY\‹œÜ]ÚYR[XYÙ\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\”™]™\œÙTÜ]Ü™\‹›Ü’Ù^Nˆ”™XY\‹œ™]™\œÙTÜ]Ü™\ˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\•™\XØ[[™š[š]TØÜ›Û›Ü’Ù^Nˆ”™XY\‹™\XØ[[™š[š]TØÜ›ÛŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\”[\˜›Ş›Ü’Ù^Nˆ”™XY\‹œ[\˜›ŞŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›Ş[[İ[
˜XÚİ\œ™XY\”[\˜›Ş[[İ[
K›Ü’Ù^Nˆ”™XY\‹œ[\˜›Ş[[İ[ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\”[\˜›ŞÜšY[][ÛŠ˜XÚİ\œ™XY\”[\˜›ŞÜšY[][ÛŠK›Ü’Ù^Nˆ”™XY\‹œ[\˜›ŞÜšY[][ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\“ÜšY[][Û“ØÚÑ[˜X›Y›Ü’Ù^Nˆœ™XY\“ÜšY[][Û“ØÚÑ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\“ÜšY[][Û“ØÚÓX\ÚÊ˜XÚİ\œ™XY\“ÜšY[][Û“ØÚÓX\ÚÊK›Ü’Ù^Nˆœ™XY\“ÜšY[][Û“ØÚÓX\ÚÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\”™XY™\ÚÛ\˜Ù[
˜XÚİ\œ™XY\”™XY™\ÚÛ\˜Ù[
K›Ü’Ù^Nˆœ™XY\”™XY™\ÚÛ\˜Ù[ŠCBƒBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y™XY\‘›ÛÚ^™J˜XÚİ\œ™XY\‘›ÛÚ^™JKBˆ›Ü’Ù^Nˆœ™XY\‘›ÛÚ^™HƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘›Û˜[Z[K›Ü’Ù^Nˆœ™XY\‘›Û˜[Z[HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘›ÛÙZYÚ›Ü’Ù^Nˆœ™XY\‘›ÛÙZYÚŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\ÛÛÜ”™\Ù]
˜XÚİ\œ™XY\ÛÛÜ”™\Ù]
K›Ü’Ù^Nˆœ™XY\ÛÛÜ”™\Ù]ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\•^[YÛ›Y[›Ü’Ù^Nˆœ™XY\•^[YÛ›Y[ŠCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y™XY\“[™TÜXÚ[™Ê˜XÚİ\œ™XY\“[™TÜXÚ[™ÊKBˆ›Ü’Ù^Nˆœ™XY\“[™TÜXÚ[™ÈƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y™XY\“X\™Ú[Š˜XÚİ\œ™XY\“X\™Ú[ŠKBˆ›Ü’Ù^Nˆœ™XY\“X\™Ú[ˆƒBˆ
CBƒBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜]]ĞÛX\ØXÚQ[˜X›Y›Ü’Ù^Nˆ˜]]ĞÛX\ØXÚQ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™Y]]ĞÛX\ØXÚU™\ÚÛPŠBˆ˜XÚİ\˜]]ĞÛX\ØXÚU™\ÚÛPƒBˆ
KBˆ›Ü’Ù^Nˆ˜]]ĞÛX\ØXÚU™\ÚÛPˆƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
Bˆ˜XÚİ\]KœØ[š]^™YYÚ]X[]U™\ÚÛ
˜XÚİ\šYÚ]X[]U™\ÚÛ
KBˆ›Ü’Ù^NˆšYÚ]X[]U™\ÚÛƒBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜˜XÚÙÜ›İ[™Ô\[[™Q[˜X›Y›Ü’Ù^Nˆ˜˜XÚÙÜ›İ[™Ô\[[™Q[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›Y›Ü’Ù^Nˆœ™XY\‘İÛ›ØYĞ˜XÚÙÜ›İ[™[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ™XY\‘İÛ›ØYÕÚYšSÛ›K›Ü’Ù^Nˆœ™XY\‘İÛ›ØYÕÚYšSÛ›HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™Y™XY\‘İÛ›ØYÔ\˜[[[Z]
˜XÚİ\œ™XY\‘İÛ›ØYÔ\˜[[[Z]
K›Ü’Ù^Nˆœ™XY\‘İÛ›ØYÔ\˜[[[Z]ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\˜]]Õ\]TÙ\šXÙ\Ñ[˜X›Y›Ü’Ù^Nˆ˜]]Õ\]TÙ\šXÙ\Ñ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›Y›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙQ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›Y›Ü’Ù^NˆœÙ\šXÙ\Ğ]]ÔÙ[Xİ\\ÛÙ\Ñ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÙ\šXÙ\Ğ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙQ[˜X›Y›Ü’Ù^Nˆ]]Ó[ÙQ\œ›Ü’[[YÙ[˜ÙTÙ][™ÜË™[˜X›YÙ^JCBˆ]™\İÜ™Y]]Ó[ÙTÛİ\˜ÙRYÈH^\š[Y[[ÛİYØØ[Ûİ\˜ÙTÙ[Xİ[Û”ÛXŞK›Y[X™\œÚ\
Bˆİ\œ™[ˆİ\œ™[]]Ó[ÙTÛİ\˜ÙRYËBˆ[˜ÛÛZ[™Îˆ˜XÚİ\œÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYËBˆ™\Ù\š[™Îˆ™\Ù\™YØØ[Ûİ\˜ÙRQÃBˆ
CBˆ]Ü™\™Y]]Ó[ÙTÛİ\˜ÙRYÈH˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
˜XÚİ\œÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÊCBˆ]™\İÜ™Y]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈH^\š[Y[[ÛİYØØ[Ûİ\˜ÙTÙ[Xİ[Û”ÛXŞK›Ü™\ŠBˆİ\œ™[ˆİ\œ™[]]Ó[ÙTÛİ\˜ÙSÜ™\’YËBˆ[˜ÛÛZ[™ÎˆÜ™\™Y]]Ó[ÙTÛİ\˜ÙRYÈ
È™\İÜ™Y]]Ó[ÙTÛİ\˜ÙRYË™š[\ˆÃBˆ[Ü™\™Y]]Ó[ÙTÛİ\˜ÙRYË˜ÛÛZ[œÊ	
CBˆKBˆ™\Ù\š[™Îˆ™\Ù\™YØØ[Ûİ\˜ÙRQÃBˆ
CBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™Y]]Ó[ÙTÛİ\˜ÙRYË›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙRYÈŠCBˆ\Ù\‘Y˜][ËœÙ]
™\İÜ™Y]]Ó[ÙTÛİ\˜ÙSÜ™\’YË›Ü’Ù^NˆœÙ\šXÙ\Ğ]]Ó[ÙTÛİ\˜ÙSÜ™\’YÈŠCBˆ\Ù\‘Y˜][ËœÙ]
]]Ó[ÙT]X[]T™Y™\™[˜ÙKœØ[š]^™Y˜]Õ˜[YJ˜XÚİ\œÙ\šXÙ\Ğ]]Ó[ÙT]X[]T™Y™\™[˜ÙJK›Ü’Ù^Nˆ]]Ó[ÙT]X[]T™Y™\™[˜ÙKœİÜ˜YÙRÙ^JCBƒBˆYˆ\Y\ÕÜ]™[Ûİ\˜Ù\ÈÃBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^NˆÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË›Z[š[][TÚ[Z[\š]RÙ^CBˆ
HÃBˆÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜËœÙ]Z[š[][TÚ[Z[\š]J˜XÚİ\œÙ\šXÙ\Ô™\İ[Z[š[][TÚ[Z[\š]JCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^NˆÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜË™›ÜZ\ÛX]ÚY™\İ[ÒÙ^CBˆ
HÃBˆÙ\šXÙ\Ô™\İ[˜[šÚ[™ÔÙ][™ÜËœÙ]›ÜÓZ\ÛX]ÚY™\İ[Ê˜XÚİ\œÙ\šXÙ\Ñ›ÜZ\ÛX]ÚY™\İ[ÊCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÈŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ][˜ÛYY[™İXYÙ\Ê˜XÚİ\œÙ\šXÙ\Ò[˜ÛYYİ™X[S[™İXYÙ\ÊCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÈŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]Y[“[™İXYÙ\Ê˜XÚİ\œÙ\šXÙ\ÒY[”İ™X[S[™İXYÙ\ÊCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]HŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]Y\Ôİ™X[\ÕÚ]İ][™İXYÙQ]J˜XÚİ\œÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ][™İXYÙQ]JCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÈŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]\Üİ[Y\ÓÜšYÚ[˜[]Y[Ê˜XÚİ\œÙ\šXÙ\Ğ\Üİ[YSÜšYÚ[˜[]Y[ÊCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\ÚŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]™X]ÑX˜™Y[š[YP\Ñ[™Û\Ú
˜XÚİ\œÙ\šXÙ\Õ™X]X˜™Y[š[YP\Ñ[™Û\Ú
CBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ÈŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]Y[”]X[]RZYÚÊ˜XÚİ\œÙ\šXÙ\ÒY[”İ™X[T]X[]Y\ÊCBˆCBˆYˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]HŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]Y\Ôİ™X[\ÕÚ]İ]]XİY]X[]J˜XÚİ\œÙ\šXÙ\ÒYTİ™X[\ÕÚ]İ]]XİY]X[]JCBˆCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œÙ\šXÙ\Ôİ™[Z[Ôİ[TÚY][˜X›Y›Ü’Ù^NˆÙ\šXÙ\ÔÚY]™\Ù[][Û”Ù][™ÜËœİ™[Z[Ôİ[Q[˜X›YÙ^JCBˆ]™\İÜ™Y^˜T[\ÔÛİ\˜ÙRYÎˆÔİš[™×OÃBˆYˆ˜XÚİ\œÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈOHš[Bˆİ\œ™[^˜T[\ÔÛİ\˜ÙRYÈOHš[ÃBƒBˆ™\İÜ™Y^˜T[\ÔÛİ\˜ÙRYÈHš[BˆH[ÙHÃBˆ]™\İÜ™Y˜\ÙHH˜XÚİ\œÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÃBˆ›X\
˜XÚİ\]KœØ[š]^™Yİš[™Ó\İ
CBˆÏÈ™\İÜ™Y]]Ó[ÙTÛİ\˜ÙSÜ™\’YÃBˆ™\İÜ™Y^˜T[\ÔÛİ\˜ÙRYÈH^\š[Y[[ÛİYØØ[Ûİ\˜ÙTÙ[Xİ[Û”ÛXŞK›Y[X™\œÚ\
Bˆİ\œ™[ˆ™\Ù\™Y^˜T[\ÓØØ[Ûİ\˜ÙRYËBˆ[˜ÛÛZ[™Îˆ™\İÜ™Y˜\ÙKBˆ™\Ù\š[™Îˆ™\Ù\™YØØ[Ûİ\˜ÙRQÃBˆ
CBˆCBˆYˆ\Y\ÕÜ]™[Ûİ\˜Ù\ËBˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ\šXÙ\Ñ^˜T[\ÔÛİ\˜ÙRYÈŠHÃBˆİ™X[S[™İXYÙQš[\‹œÙ]^˜T[\ÔÛİ\˜ÙRYÊ™\İÜ™Y^˜T[\ÔÛİ\˜ÙRYÊCBˆCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›Y›Ü’Ù^Nˆ™Ú]X”™[X\ÙP]]ĞÚXÚÑ[˜X›YŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙU\]P]˜Z[X›K›Ü’Ù^Nˆ™Ú]X”™[X\ÙU\]P]˜Z[X›HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙS]\İ™\œÚ[Û‹›Ü’Ù^Nˆ™Ú]X”™[X\ÙS]\İ™\œÚ[ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙUT“›Ü’Ù^Nˆ™Ú]X”™[X\ÙUT“ŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙTÚİĞ[\[™[™Ë›Ü’Ù^Nˆ™Ú]X”™[X\ÙTÚİĞ[\[™[™ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[Û‹›Ü’Ù^Nˆ™Ú]X”™[X\ÙS\İ›Û\Y™\œÚ[ÛˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\™š[\’Üœ›ÜÛÛ[›Ü’Ù^Nˆ™š[\’Üœ›ÜˆŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\]KœØ[š]^™YÚ[Z[\š]P[ÛÜš]J˜XÚİ\œÙ[XİYÚ[Z[\š]P[ÛÜš]JK›Ü’Ù^NˆœÙ[XİYÚ[Z[\š]P[ÛÜš]HŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\šØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQ›Ü’Ù^NˆšØ[™[’ÛYTÙ[XİYÛİ\˜ÙRQŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\šØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\Ë›Ü’Ù^NˆšØ[™[”™XÙ[Ûİ\˜ÙTÙX\˜Ú\ÈŠCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ\™›Ü›X[˜ÙS[ÙQ[˜X›Y›Ü’Ù^Nˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™[˜X›YÙ^JCBˆ\Ù\‘Y˜][ËœÙ]
˜XÚİ\œ\™›Ü›X[˜ÙS[ÙTÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[Ë›Ü’Ù^Nˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜËœÚÚ\[šS\İ˜]™\œØ[›Ü[š[YQ]Z[ÒÙ^JCBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^Nˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™˜\İ[š[YPØ][ÙÓİ™\œšY\ÒÙ^CBˆ
HÃBˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™˜\İ[š[YPØ][ÙÓİ™\œšY\ÈH˜XÚİ\œ\™›Ü›X[˜ÙS[ÙQ˜\İ[š[YPØ][ÙÓİ™\œšY\ÃBˆCBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ˜XÚİ\œÙX\˜Ú\İÜKØ\ĞØ\\™YX˜XÚİ\œÙX\˜Ú\İÜKœ]Y\šY\Ëš\Ñ[\KBˆ]ÙX\˜Ú\İÜQ]HHOÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJ˜XÚİ\œÙX\˜Ú\İÜKœ]Y\šY\ÊHÃBˆ\Ù\‘Y˜][ËœÙ]
ÙX\˜Ú\İÜQ]K›Ü’Ù^NˆœÙX\˜Ú\İÜHŠCBˆCBˆ\™›Ü›SÛ“XZ[•™XYÃBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^Nˆ™š[\’Üœ›ÜˆŠHÃBˆQÛÛ[š[\‹œÚ\™Y™š[\’Üœ›ÜˆH˜XÚİ\™š[\’Üœ›ÜÛÛ[BˆCBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KBˆ˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JİÜ˜YÙRÙ^NˆœÙ[XİYÚ[Z[\š]P[ÛÜš]HŠHÃBˆ[ÛÜš]SX[˜YÙ\‹œÚ\™YœÙ[XİY[ÛÜš]HHÚ[Z[\š]P[ÛÜš]J˜]Õ˜[YNˆ˜XÚİ\]KœØ[š]^™YÚ[Z[\š]P[ÛÜš]J˜XÚİ\œÙ[XİYÚ[Z[\š]P[ÛÜš]JJHÏÈšXœšYBˆCBƒBˆ]Ù][™ÜÈHÙ][™ÜËœÚ\™YBˆ][YHHXÛ\ÙU[YKœÚ\™YBˆÙ][™ÜË›Øš™XİÚ[Ú[™ÙKœÙ[™

CBˆ[YK›Øš™XİÚ[Ú[™ÙKœÙ[™

CBˆCBƒBˆYˆ\Y\ÕÜ]™[ÛÛXİ[ÛœÈÃBˆ]™\İÜ™YÛÛXİ[ÛœÈH˜XÚİ\˜ÛÛXİ[ÛœË›X\È	ÓXœ˜\PÛÛXİ[ÛŠ
HCBˆ\™›Ü›SÛ“XZ[•™XYÃBƒBˆXœ˜\SX[˜YÙ\‹œÚ\™Yœ™\XÙPÛÛXİ[ÛœÑ›Ü“YYXTİ]J™\İÜ™YÛÛXİ[ÛœÊCBˆCBˆCBƒBˆYˆ\Y\ÕÜ]™[›ÙÜ™\ÜÈÃBˆ]›ÙÜ™\ÜÓX[˜YÙ\ˆH›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™YBˆ›ÙÜ™\ÜÓX[˜YÙ\‹œ™\XÙT›ÙÜ™\ÜÑ]Q›Ü”™\İÜ™JBˆ˜XÚİ\]KœØ[š]^™Y›ÙÜ™\ÜÑ]JBˆ˜XÚİ\œ›ÙÜ™\ÜÑ]KBˆ™\Ù\š[™Ñ]šXÙSØØ[™Y™\™[˜Ù\ÎˆYCBˆ
KBˆ^XİY›Ùš[RQˆXİ]™T›Ùš[RQBˆ
CBˆCBƒBˆYˆ\Y\ÕÜ]™[˜XÚÙ\‹BˆÜ]™[Û˜\ÚİË˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YOHYHÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]™\İÜ™Y˜XÚÙ\”İ]HHÜ]™[Û˜\ÚİË˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YOHYCBˆÈÜ]™[Û˜\ÚİË˜XÚÙ\”İ]HÏÈ˜XÚİ\˜XÚÙ\”İ]CBˆˆ˜XÚİ\˜XÚÙ\”İ]CBˆÈH˜XÚÙ\“X[˜YÙ\‹˜\T™\İÜ™Y˜XÚÙ\”İ]JBˆ™\İÜ™Y˜XÚÙ\”İ]KBˆ›Ü”›Ùš[NˆXİ]™T›Ùš[RQBˆÜ™Y[X[Ğ[™›Üİ\\™P]]Üš]]]™NƒBˆÜ]™[Û˜\ÚİË˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YOHYCBˆ
CBˆCBˆCBƒBˆ]™\İÜ™Y\™›Ü›X[˜ÙS[ÙQ[˜X›YH˜XÚİ\Ü]™[Ù][™Ò\Ğ]]Üš]]]™JBˆİÜ˜YÙRÙ^Nˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜË™[˜X›YÙ^CBˆ
HÈ˜XÚİ\œ\™›Ü›X[˜ÙS[ÙQ[˜X›Yˆ\™›Ü›X[˜ÙS[ÙTÙ][™ÜËš\Ñ[˜X›YBˆYˆX\Y\ÕÜ]™[\”›Ùš[Q]HÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆØ][ÙÓX[˜YÙ\‹œÚ\™YœÙ]\™›Ü›X[˜ÙS[ÙQ[˜X›Y
\™›Ü›X[˜ÙS[ÙTÙ][™ÜËš\Ñ[˜X›Y
CBˆCBˆH[ÙHYˆ\Y\ÕÜ]™[Ø][ÙÜË˜XÚİ\˜Ø][ÙÜËš\Ñ[\HÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆØ][ÙÓX[˜YÙ\‹œÚ\™Yœ™\XÙPØ][ÙÜÑ›Ü“YYXTİ]J×JCBˆØ][ÙÓX[˜YÙ\‹œÚ\™YœÙ]\™›Ü›X[˜ÙS[ÙQ[˜X›Y
™\İÜ™Y\™›Ü›X[˜ÙS[ÙQ[˜X›Y
CBˆCBˆH[ÙHYˆ\Y\ÕÜ]™[Ø][ÙÜÈÃBˆ˜\ˆY\™ÙYH˜XÚİ\˜Ø][ÙÜÃBˆ]^\İ[™ÒYÈHÙ]
Y\™ÙY›X\È	šYJCBˆ˜\ˆİ\œ™[Y˜][ÎˆĞØ][Ù×HH×CBˆ\™›Ü›SÛ“XZ[•™XYÃBˆİ\œ™[Y˜][ÈHØ][ÙÓX[˜YÙ\‹œÚ\™Y˜Ø][ÙÜË™š[\ˆÈY^\İ[™ÒYË˜ÛÛZ[œÊ	šY
HCBˆCBˆY\™ÙY˜\[™
ÛÛ[ÓÙˆİ\œ™[Y˜][ÊCBˆY\™ÙYHY\™ÙY™[[Y\˜]Y

K›X\È[™^Ø][ÙÈ[ƒBˆ˜\ˆ\]YHØ][ÙÃBˆ\]Y›Ü™\ˆH[™^Bˆ™]\›ˆ\]YBˆCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]Ø][ÙÓX[˜YÙ\ˆHØ][ÙÓX[˜YÙ\‹œÚ\™YBˆØ][ÙÓX[˜YÙ\‹œÙ]\™›Ü›X[˜ÙS[ÙQ[˜X›Y
™\İÜ™Y\™›Ü›X[˜ÙS[ÙQ[˜X›Y
CBˆØ][ÙÓX[˜YÙ\‹˜Ø][ÙÜÈHY\™ÙYBˆØ][ÙÓX[˜YÙ\‹œØ]™PØ][ÙÜÊ
CBˆCBˆH[ÙHÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]Ø][ÙÓX[˜YÙ\ˆHØ][ÙÓX[˜YÙ\‹œÚ\™YBˆØ][ÙÓX[˜YÙ\‹œÙ]\™›Ü›X[˜ÙS[ÙQ[˜X›Y
™\İÜ™Y\™›Ü›X[˜ÙS[ÙQ[˜X›Y
CBˆØ][ÙÓX[˜YÙ\‹œØ]™PØ][ÙÜÊ
CBˆCBˆCBƒBˆ\TÚ\™TÙ\šXÙ\Ó[ÙRY“™YYY
˜XÚİ\
CBƒBˆ]Ù\šXÙTİÜ™HHÙ\šXÙTİÜ™KœÚ\™YBˆ]\Y\ÕÜ]™[Ù\šXÙ\ÈH\Y\ÕÜ]™[Ûİ\˜Ù\È	‰ˆ˜XÚİ\š\ÔÙ\šXÙ\ÃBˆ]^\İ[™ÔÙ\šXÙ\ÈH\Y\ÕÜ]™[Ù\šXÙ\ÈÈÙ\šXÙTİÜ™K™Ù]Ù\šXÙ\Ê
Hˆ×CBˆ][˜ÛÛZ[™ÔÙ\šXÙ\ÈH
\Y\ÕÜ]™[Ù\šXÙ\ÈÈ˜XÚİ\œÙ\šXÙ\Èˆ×JKœÛÜY
NˆÃBˆYˆ	œÛÜ[™^OH	KœÛÜ[™^ÃBˆ™]\›ˆ	šY]ZYİš[™È	KšY]ZYİš[™ÃBˆCBˆ™]\›ˆ	œÛÜ[™^	KœÛÜ[™^BˆJCBˆ]Ù\šXÙ\ÕÔ™\İÜ™NˆĞ˜XÚİ\Ù\šXÙWCBˆ˜\ˆ]šXÙSØØ[Ù\šXÙRQÈHÙ]URQŠ
CBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ]İ\œ™[Ù\šXÙ\ÈH^\İ[™ÔÙ\šXÙ\Ë›X\ÈÙ\šXÙH[ƒBˆ]Y]Y]HH
OÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJÙ\šXÙK›Y]Y]JJCBˆ™›]X\Èİš[™Ê]Nˆ	[˜ÛÙ[™Îˆ]
HHÏÈˆƒBˆ™]\›ˆ˜XÚİ\Ù\šXÙJBˆYˆÙ\šXÙKšYBˆ\›ˆÙ\šXÙK\›BˆœÛÛ“Y]Y]NˆY]Y]KBˆœÔØÜš\ˆÙ\šXÙKšœÔØÜš\Bˆ\ĞXİ]™NˆÙ\šXÙKš\ĞXİ]™KBˆÛÜ[™^ˆÙ\šXÙKœÛÜ[™^Bˆ
CBˆCBˆ]šXÙSØØ[Ù\šXÙRQÈHÙ]
İ\œ™[Ù\šXÙ\Ë˜ÛÛ\XİX\ÈÙ\šXÙH[ƒBˆ˜XÚİ\]KœÙ\šXÙQ›Ü‘^\š[Y[[ÛİYŞ[˜ÊÙ\šXÙJHOHš[ÈÙ\šXÙKšYˆš[BˆJCBˆÙ\šXÙ\ÕÔ™\İÜ™HH^\š[Y[[ÛİYÛİ\˜ÙT™\İÜ™TÛXŞKœÙ\šXÙ\ÊBˆİ\œ™[ˆİ\œ™[Ù\šXÙ\ËBˆ[˜ÛÛZ[™Îˆ[˜ÛÛZ[™ÔÙ\šXÙ\ÃBˆ
CBˆH[ÙHÃBˆÙ\šXÙ\ÕÔ™\İÜ™HH[˜ÛÛZ[™ÔÙ\šXÙ\ÃBˆCBˆ]Ù\šXÙ\ÕÔ™[[İ™HH™Yœ™\ÚÛİYÛİ\˜Ù\ÃBˆÈ^\İ[™ÔÙ\šXÙ\Ë™š[\ˆÈY]šXÙSØØ[Ù\šXÙRQË˜ÛÛZ[œÊ	šY
HCBˆˆ^\İ[™ÔÙ\šXÙ\ÃBˆÙ\šXÙ\ÕÔ™[[İ™K™›Ü‘XXÚÈÙ\šXÙTİÜ™Kœ™[[İ™J	
HCBˆ›Üˆİ˜È[ˆÙ\šXÙ\ÕÔ™\İÜ™HÚ\™HY]šXÙSØØ[Ù\šXÙRQË˜ÛÛZ[œÊİ˜ËšY
HÃBƒBˆİX\™]ØÜš\HÙ\šXÙTİÜ™TØÛÜKœÙXİ\™YØÜš\›Ü”™\İÜ™JBˆİ˜ËšœÔØÜš\BˆÙ\šXÙRQˆİ˜ËšYBˆ›Ùš[RQˆXİ]™T›Ùš[RQBˆ
H[ÙHÈÛÛ[YHCBˆÙ\šXÙTİÜ™KœİÜ™TÙ\šXÙJBˆYˆİ˜ËšYBˆ\›ˆİ˜Ë\›BˆœÛÛ“Y]Y]Nˆİ˜ËšœÛÛ“Y]Y]KBˆœÔØÜš\ˆØÜš\Bˆ\ĞXİ]™Nˆİ˜Ëš\ĞXİ]™KBˆÛÜ[™^ˆİ˜ËœÛÜ[™^Bˆ
CBˆCBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ][]Y\ÈHÙ\šXÙTİÜ™K™Ù][]Y\Ê
CBˆ›Üˆ
[™^Ù\šXÙJH[ˆÙ\šXÙ\ÕÔ™\İÜ™K™[[Y\˜]Y

HÃBˆ[]Y\Ë™š\œİ
Ú\™NˆÈ	šYOHÙ\šXÙKšYJOËœÛÜ[™^H[
[™^
CBˆCBˆÙ\šXÙTİÜ™KœØ]™J
CBˆCBƒBˆYˆ\Y\ÕÜ]™[Ûİ\˜Ù\Ë]İ™[Z[ĞYÛœÈH˜XÚİ\œİ™[Z[ĞYÛœÈÃBˆ]İ™[Z[ÔİÜ™HHİ™[Z[ĞYÛ”İÜ™KœÚ\™YBˆ][˜ÛÛZ[™ĞYÛœÈHİ™[Z[ĞYÛœËœÛÜYÃBˆYˆ	œÛÜ[™^OH	KœÛÜ[™^ÃBˆ™]\›ˆ	šY]ZYİš[™È	KšY]ZYİš[™ÃBˆCBˆ™]\›ˆ	œÛÜ[™^	KœÛÜ[™^BˆCBˆ]YÛœÕÔ™\İÜ™NˆĞ˜XÚİ\İ™[Z[ĞYÛ—CBˆ˜\ˆ]šXÙSØØ[YÛ’QÈHÙ]URQŠ
CBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ]İ\œ™[YÛœÈHİ™[Z[ÔİÜ™K™Ù]YÛœÊ
K›X\ÈYÛˆ[ƒBˆ]X[šY™\İ”ÓÓˆH
OÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJYÛ‹›X[šY™\İ
JCBˆ™›]X\Èİš[™Ê]Nˆ	[˜ÛÙ[™Îˆ]
HHÏÈˆƒBˆ™]\›ˆ˜XÚİ\İ™[Z[ĞYÛŠBˆYˆYÛ‹šYBˆÛÛ™šYİ\™YT“ˆYÛ‹˜ÛÛ™šYİ\™YT“BˆX[šY™\İ”ÓÓˆX[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™NˆYÛ‹š\ĞXİ]™KBˆÛÜ[™^ˆYÛ‹œÛÜ[™^Bˆ
CBˆCBˆ]šXÙSØØ[YÛ’QÈHÙ]
İ\œ™[YÛœË˜ÛÛ\XİX\ÈYÛˆ[ƒBˆ˜XÚİ\]Kœİ™[Z[ĞYÛ‘›Ü‘^\š[Y[[ÛİYŞ[˜ÊYÛŠHOHš[ÈYÛ‹šYˆš[BˆJCBˆYÛœÕÔ™\İÜ™HH^\š[Y[[ÛİYÛİ\˜ÙT™\İÜ™TÛXŞKœİ™[Z[ĞYÛœÊBˆİ\œ™[ˆİ\œ™[YÛœËBˆ[˜ÛÛZ[™Îˆ[˜ÛÛZ[™ĞYÛœÃBˆ
CBˆH[ÙHÃBˆYÛœÕÔ™\İÜ™HH[˜ÛÛZ[™ĞYÛœÃBˆCBƒBˆ]™\ÛÛ™YT“ĞPYÛ’QˆÕURQˆİš[™×HHYÛœÕÔ™\İÜ™Kœ™YXÙJ[ÎˆÎ—JHÈ™\İ[YÛˆ[ƒBˆ]™\ÛÛ™YHİ™[Z[ĞÛÛ™šYİ\™YT“˜][œ™\ÛÛ™JBˆYÛ’QˆYÛ‹šYBˆ\œÚ\İYT“ˆYÛ‹˜ÛÛ™šYİ\™YT“Bˆ
CBˆİX\™™\ÛÛ™YOHYÛ‹˜ÛÛ™šYİ\™YT“[ÙHÈ™]\›ˆCBˆ™\İ[ØYÛ‹šYHH™\ÛÛ™YBˆCBƒBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ›ÜˆYÛˆ[ˆİ™[Z[ÔİÜ™K™Ù]YÛœÊ
HÚ\™HY]šXÙSØØ[YÛ’QË˜ÛÛZ[œÊYÛ‹šY
HÃBˆİ™[Z[ÔİÜ™Kœ™[[İ™JYÛŠCBˆCBˆH[ÙHÃBˆİ™[Z[ÔİÜ™Kœ™[[İ™P[

CBˆCBƒBˆ›ÜˆYÛˆ[ˆYÛœÕÔ™\İÜ™HÚ\™HY]šXÙSØØ[YÛ’QË˜ÛÛZ[œÊYÛ‹šY
HÃBƒBˆ]İÜ™YT“H™\ÛÛ™YT“ĞPYÛ’QØYÛ‹šYHÏÈYÛ‹˜ÛÛ™šYİ\™YT“Bˆ]ÛÛ™šYİ\™YT“HİÜ™YT“š[[Z[™ĞÚ\˜Xİ\œÊ[ˆÚ]\ÜXÙ\Ğ[™™]Û[™\ÊCBˆYˆİ™[Z[ĞÛÛ™šYİ\™YT“˜][š\Õ[œ™\ÛÛ™Y™Y™\™[˜ÙJÛÛ™šYİ\™YT“
HÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ”ÚÚ\[™Èİ™[Z[ÈYÛˆ
YÛ‹šY
Hœ›ÛH˜XÚİ\ˆ]ÈÛÛ™šYİ\™YT“Ø\ÈİÜ™Y[ˆ\È]šXÙIÜÈÙ^XÚZ[ˆ[™\È›İ[ˆH˜XÚİ\ˆ™KXY]È™\İÜ™H]ˆ‹Bˆ\Nˆ”İ™[Z[ÈƒBˆ
CBˆÛÛ[YCBˆCBˆİX\™XÛÛ™šYİ\™YT“š\Ñ[\KBˆ]X[šY™\İ]HHYÛ‹›X[šY™\İ”ÓÓ‹™]J\Ú[™Îˆ]
KBˆ]X[šY™\İHOÈ”ÓÓ‘XÛÙ\Š
K™XÛÙJİ™[Z[ÓX[šY™\İœÙ[‹œ›ÛNˆX[šY™\İ]JKBˆX[šY™\İœİ\ÜÒ[œİ[X›T™\Ûİ\˜Ù\È[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊ”ÚÚ\[™È[˜[Yİ™[Z[ÈYÛˆœ›ÛH˜XÚİ\ˆ
YÛ‹šY
H‹\Nˆ”İ™[Z[ÈŠCBˆÛÛ[YCBˆCBƒBˆİ™[Z[ÔİÜ™KœİÜ™PYÛŠBˆYˆYÛ‹šYBˆÛÛ™šYİ\™YT“ˆÛÛ™šYİ\™YT“BƒBˆX[šY™\İ”ÓÓˆYÛ‹›X[šY™\İ”ÓÓ‹Bˆ\ĞXİ]™NˆYÛ‹š\ĞXİ]™KBˆÛÜ[™^ˆYÛ‹œÛÜ[™^Bˆ
CBˆCBˆYˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÃBˆ][]Y\ÈHİ™[Z[ÔİÜ™K™Ù][]Y\Ê
CBˆ›Üˆ
[™^YÛŠH[ˆYÛœÕÔ™\İÜ™K™[[Y\˜]Y

HÃBˆ[]Y\Ë™š\œİ
Ú\™NˆÈ	šYOHYÛ‹šYJOËœÛÜ[™^H[
[™^
CBˆCBˆİ™[Z[ÔİÜ™KœØ]™J
CBˆCBƒBˆCBƒBˆYˆ\Y\ÕÜ]™[X[™ØPÛÛXİ[ÛœË˜XÚİ\š\ÓX[™ØPÛÛXİ[ÛœÈÃBˆ]™\İÜ™YX[™ØPÛÛXİ[ÛœÈH˜XÚİ\›X[™ØPÛÛXİ[ÛœË›X\È˜È[ƒBˆX[™ØSXœ˜\PÛÛXİ[ÛŠYˆ˜ËšY˜[YNˆ˜Ë›˜[YK][\Îˆ˜Ëš][\Ë\ØÜš\[Ûˆ˜Ë™\ØÜš\[ÛŠCBˆCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆX[™ØSXœ˜\SX[˜YÙ\‹œÚ\™Y˜ÛÛXİ[ÛœÈH™\İÜ™YX[™ØPÛÛXİ[ÛœÃBˆCBˆCBƒBˆYˆ\Y\ÕÜ]™[X[™ØT›ÙÜ™\ÜË˜XÚİ\š\ÓX[™ØT™XY[™Ô›ÙÜ™\ÜÈÃBˆ]X[™ØT›ÙÜ™\ÜÓX\HXİ[Û˜\JBˆ˜XÚİ\›X[™ØT™XY[™Ô›ÙÜ™\ÜË˜ÛÛ\XİX\ÈÙ^K˜[YHOˆ
[X[™ØT›ÙÜ™\ÜÊOÈ[ƒBˆİX\™]YH[
Ù^JH[ÙHÈ™]\›ˆš[CBˆ™]\›ˆ
Y˜[YJCBˆKBˆ[š\]Z[™ÒÙ^\ÕÚ]ˆÈË[˜ÛÛZ[™È[ˆ[˜ÛÛZ[™ÈCBˆ
CBˆ\™›Ü›SÛ“XZ[•™XYÃBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Yœ™\XÙT›ÙÜ™\ÜÓX\›Ü”™\İÜ™JX[™ØT›ÙÜ™\ÜÓX\
CBˆCBˆCBƒBˆYˆ\Y\ÕÜ]™[X[™ØPØ][ÙÜË˜XÚİ\š\ÓX[™ØPØ][ÙÜÈÃBˆ]X[™ØPØ][ÙÓX[˜YÙ\ˆHX[™ØPØ][ÙÓX[˜YÙ\‹œÚ\™YBˆX[™ØPØ][ÙÓX[˜YÙ\‹˜Ø][ÙÜÈH˜XÚİ\›X[™ØPØ][ÙÜÃBˆX[™ØPØ][ÙÓX[˜YÙ\‹œØ]™PØ][ÙÜÊ
CBˆCBƒBˆYˆ\Y\ÕÜ]™[İ\İÛPØ][ÙÜË˜XÚİ\š\Ğİ\İÛPØ][ÙÜÈÃBˆ]™\İÜ™Yİ\İÛPØ][ÙÜÈH˜XÚİ\˜İ\İÛPØ][ÙÜÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆØ[™[İ\İÛPØ][ÙÓX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™YØ][ÙÜÊBˆ™\İÜ™Yİ\İÛPØ][ÙÜËBˆ›Ü”›Ùš[NˆXİ]™T›Ùš[RQBˆ
CBˆCBˆCBƒBˆYˆ˜XÚİ\š\ÒØ[™[“[Ù[\ÈÃBˆ]™\İÜ™Y[Ù[\ÈH˜XÚİ\šØ[™[“[Ù[\Ë›X\È[Ù[ƒBˆ[Ù[Q]PÛÛZ[™\ŠBˆYˆ[ÙšYBˆ[Ù[Q]Nˆ[Ù›[Ù[Q]KBˆØØ[]ˆ[Ù›ØØ[]Bˆ[Ù[]\›ˆ[Ù›[Ù[]\›Bˆ\ĞXİ]™Nˆ[Ùš\ĞXİ]™CBˆ
CBˆCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]Ø[™[“[Ù[SX[˜YÙ\ˆH[Ù[SX[˜YÙ\‹œÚ\™YBˆØ[™[“[Ù[SX[˜YÙ\‹œ™\XÙS[Ù[\Ñ›Ü”™\İÜ™J™\İÜ™Y[Ù[\ÊCBˆØ[™[“[Ù[SX[˜YÙ\‹œØ]™S[Ù[\Ê
CBˆCBˆCBƒBˆÚYˆ[ÜÊ“ÔÊCBˆYˆ\Y\ÕÜ]™[Ûİ\˜Ù\ËBˆÜ]™[Û˜\ÚİËœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HOHš[Bˆ]™XY\”İ]HH˜XÚİ\œ™XY\‘^[œÚ[ÛœÔİ]CBˆÏÈ˜XÚİ\˜ZYÚİTİ]K›X\
˜XÚİ\™XY\‘^[œÚ[Û”İ]K›ZYÜ˜][™ÓYØXŞPZYÚİJHÃBˆÈHÙ[‹œ™\İÜ™T™XY\‘^[œÚ[Û”İ]T™\Ù\š[™ÓØØ[Û‘˜Z[\™JBˆ™XY\”İ]KBˆY]Y]TİÜ™Nˆ›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ËBˆ™Y™\™[˜ÙTİÜ™Nˆ›Ùš[TÙ][™ÜÔİÜ™K˜Xİ]™KBˆÛÛ^ˆ˜Xİ]™H›Ùš[HƒBˆ
CBˆCBˆÙ[™YƒBƒBˆYˆ\Y\ÕÜ]™[\”›Ùš[Q]KX˜XÚİ\œ™XÛÛ[Y[™][ÛØXÚKš\Ñ[\HÃBˆ™XÛÛ[Y[™][Û‘[™Ú[™KœÚ\™Yœ™\İÜ™T™XÛÛ[Y[™][ÛØXÚJ˜XÚİ\œ™XÛÛ[Y[™][ÛØXÚJCBˆCBƒBˆYˆ\Y\ÕÜ]™[˜][™ÜË˜XÚİ\š\Õ\Ù\”˜][™ÜÈÃBˆ\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ™\İÜ™T˜][™ÜĞ[™›İ\ÊBˆ˜][™ÜÎˆ˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™ÜÊ˜XÚİ\\Ù\”˜][™ÜÊKBˆ›İ\Îˆ˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™Ó›İ\Ê˜XÚİ\\Ù\”˜][™Ó›İ\ÊCBˆ
CBˆCBƒBˆYˆ\Y\ÕÜ]™[Ûİ\˜Ù\Ë]Ù\šXÙ\ÔÙ][™ÜÈH˜XÚİ\œÙ\šXÙ\ÔÙ][™ÜÈÃBˆ]İÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÙ\šXÙ\ÃBˆÙ[‹œ™\İÜ™TÙ\šXÙ\ÔÙ][™ÜÊBˆÙ\šXÙ\ÔÙ][™ÜËBˆØ\\™YÛÛ\][Nˆ˜XÚİ\œÙ\šXÙ\ÔÙ][™ÜÕÙ\™PØ\\™YBˆÎˆİÜ™KBˆ™\Ù\š[™Îˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÈÈ™\Ù\™YØØ[Ûİ\˜ÙRQÈˆ×CBˆ
CBˆCBƒBˆ™\İÜ™TÚ\™YÛİ\˜ÙT^[ØYÊ˜XÚİ\
CBƒBˆ]š]˜]PÛÛ™šYİ\˜][Û”™\İÜ™HH™\İÜ™T›Ùš[TÛ˜\ÚİÊBˆ˜XÚİ\Bˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]Nˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KBˆ™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]Nˆ™Yœ™\ÚÛİYÛİ\˜Ù\ÃBˆ
CBˆİX\™š]˜]PÛÛ™šYİ\˜][Û”™\İÜ™KØ\Ô™\İÜ™Y[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆš]˜]HÛİYÛÛ™šYİ\˜][ÛˆY›İ\œÚ\İ\˜X›NÈ™\İÜ™H™\]Z\™\È›Û˜XÚÈ‹Bˆ\NˆÛİYŞ[˜ÈƒBˆ
CBˆ™]\›ˆš[BˆCBƒBˆİX\™›Ùš[SX[˜YÙ\‹œÚ\™Yœ›Üİ\”İÜ™R\Ô™XYX›H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™\İÜ™HY›İÛÛZ[ˆH˜[Y›Ùš[H›Üİ\ÈH[œ™XYX›HØØ[›Üİ\ˆ™[XZ[œÈ]X\˜[[™Y‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆ™]\›ˆš[BˆCBƒBˆÚYˆÜÊSÔÊCBˆ\ÚÈÈXZ[XİÜˆ[ƒBˆ]ØZ]ØØ[›İYšXØ][Û“X[˜YÙ\‹œÚ\™Yœ™[ØY\œÚ\İYÙ[Xİ[ÛœĞY\”™\İÜ™J
CBˆCBˆÙ[™YƒBƒBˆÙÙÙ\‹œÚ\™Y›ÙÊ˜XÚİ\™\İÜ™YİXØÙ\ÜÙ[H‹\Nˆ’[™›ÈŠCBˆ™]\›ˆ˜XÚİ\\XØ][Û”™\İ[
Bˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎƒBˆš]˜]PÛÛ™šYİ\˜][Û”™\İÜ™K˜]]Üš]]]™U˜XÚÙ\”›Ùš[RQÃBˆ
CBˆCBƒBˆİ]XÈ]X^[][T›Ùš[S˜[YUU]\ÈH›Ùš[SX[˜YÙ\‹›X^[][S˜[YUU]\ÃBˆİ]XÈ]X^[][T›Ùš[P]˜]\”Ş[X›ÛU]\ÈH›Ùš[SX[˜YÙ\‹›X^[][P]˜]\”Ş[X›ÛU]\ÃBƒBˆİ]XÈ[˜ÈØ[š]^™Y›Ùš[TÛ˜\Úİ›Ü”™\İÜ™JBˆÈÛİ\˜ÙNˆ˜XÚİ\›Ùš[TÛ˜\ÚİBˆ›İÎˆ]HH]J
CBˆ
HOˆ˜XÚİ\›Ùš[TÛ˜\ÚİÈÃBˆ˜\ˆÛ˜\ÚİHÛİ\˜ÙCBˆİX\™]˜[YHH›Ùš[SX[˜YÙ\‹œØ[š]^™Y˜[YJÛİ\˜ÙK›˜[YJH[ÙHÈ™]\›ˆš[CBˆÛ˜\Úİ›˜[YHH˜[YCBˆÛ˜\Úİ˜]˜]\”Ş[X›ÛH›Ùš[SX[˜YÙ\‹œØ[š]^™Y]˜]\”Ş[X›Û
Ûİ\˜ÙK˜]˜]\”Ş[X›Û
CBˆÛ˜\Úİ˜]˜]\ÛÛÜ’^H›Ùš[SX[˜YÙ\‹œØ[š]^™Y]˜]\ÛÛÜ’^
Ûİ\˜ÙK˜]˜]\ÛÛÜ’^
CBˆYˆÛ˜\Úİ˜]˜]\”İÑ]OËš\Ñ[\HOHYCBˆ
Û˜\Úİ˜]˜]\”İÑ]OË˜Ûİ[ÏÈ
Hˆ›Ùš[P]˜]\‹›X^[][TİĞ]\ÈÃBˆÛ˜\Úİ˜]˜]\”İÑ]HHš[BˆCBƒBˆ]Ø[š]^™YS’\ÚH›Ùš[TS’\Ú\‹œØ[š]^™Y\Ú
Ûİ\˜ÙKœ[’\Ú
CBˆÛ˜\Úİœ[’\ÚHØ[š]^™YS’\ÚBˆÛ˜\Úİ˜Ü™X]Y]HØ[š]^™Y™\]Z\™Y›Ùš[PÛØÚÊÛİ\˜ÙK˜Ü™X]Y]›İÎˆ›İÊCBˆÛ˜\Úİœ[Ú[™ÙY]HØ[š]^™YS’\ÚOHš[	‰ˆÛİ\˜ÙKœ[’\ÚOHš[BˆÈš[BˆˆØ[š]^™YÜ[Û˜[›Ùš[PÛØÚÊÛİ\˜ÙKœ[Ú[™ÙY]›İÎˆ›İÊCBˆÛ˜\ÚİšÚYÑ›YĞÚ[™ÙY]HØ[š]^™YÜ[Û˜[›Ùš[PÛØÚÊBˆÛİ\˜ÙKšÚYÑ›YĞÚ[™ÙY]Bˆ›İÎˆ›İÃBˆ
CBˆÛ˜\Úİœ™XY\‘^[œÚ[ÛœÔİ]HH
BˆÛİ\˜ÙKœ™XY\‘^[œÚ[ÛœÔİ]CBˆÏÈÛİ\˜ÙK˜ZYÚİTİ]K›X\
˜XÚİ\™XY\‘^[œÚ[Û”İ]K›ZYÜ˜][™ÓYØXŞPZYÚİJCBˆ
OËœØ[š]^™Y

CBˆÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HH˜XÚİ\›Ùš[TÛ˜\ÚİBˆ˜›İ[™Y™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]JBˆÛİ\˜ÙKœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]CBˆ
CBˆÛ˜\Úİ˜ZYÚİTİ]HHš[BˆÛ˜\ÚİœÙ\šXÙ\ÔÙ][™ÜÈH˜XÚİ\]KœÙ\šXÙ\ÔÙ][™ÜÑ›Ü‘^\š[Y[[ÛİYŞ[˜ÊBˆÛİ\˜ÙKœÙ\šXÙ\ÔÙ][™ÜÃBˆ
HÏÈÎ—CBˆ™]\›ˆÛ˜\ÚİBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ[š]^™Y™\]Z\™Y›Ùš[PÛØÚÊÈ˜[YNˆ]K›İÎˆ]JHOˆ]HÃBˆ]ÙXÛÛ™ÈH˜[YK[YR[\˜[Ú[˜ÙLNMÌBˆ]X^[][HH›İË[YR[\˜[Ú[˜ÙLNMÌBˆ
ÈYYXTİ]Q[™[ÜU˜[Y]Ü‹›X^[][Q]\™PÛØÚÔÚÙ]ÃBˆİX\™ÙXÛÛ™Ëš\Ñš[š]H[ÙHÈ™]\›ˆ›İÈCBˆYˆÙXÛÛ™ÈÈ™]\›ˆ]J[YR[\˜[Ú[˜ÙLNMÌˆ
HCBˆYˆÙXÛÛ™ÈˆX^[][HÈ™]\›ˆ›İÈCBˆ™]\›ˆ˜[YCBˆCBƒBˆš]˜]Hİ]XÈ[˜ÈØ[š]^™YÜ[Û˜[›Ùš[PÛØÚÊÈ˜[YNˆ]OË›İÎˆ]JHOˆ]OÈÃBˆİX\™]˜[YH[ÙHÈ™]\›ˆš[CBˆ]ÙXÛÛ™ÈH˜[YK[YR[\˜[Ú[˜ÙLNMÌBˆ]X^[][HH›İË[YR[\˜[Ú[˜ÙLNMÌBˆ
ÈYYXTİ]Q[™[ÜU˜[Y]Ü‹›X^[][Q]\™PÛØÚÔÚÙ]ÃBˆİX\™ÙXÛÛ™Ëš\Ñš[š]KÙXÛÛ™ÈH[ÙHÈ™]\›ˆš[CBˆ™]\›ˆÙXÛÛ™ÈˆX^[][HÈ›İÈˆ˜[YCBˆCBƒBˆİ]XÈ[˜È›Ùš[TÛ˜\ÚİĞYZ]Y›Ü”™\İÜ™JBˆÈÛ˜\ÚİÎˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİKBˆ^\İ[™Ô›Ùš[RQÎˆÙ]URQ‹BˆYZ][™Õ[œ›Üİ\™Yš]˜]PÛÛ™šYİ\˜][Ûˆ›ÛÛH˜[ÙCBˆ
HOˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİHÃBˆ˜\ˆÙY[’QÈHÙ]URQŠ
CBˆ˜\ˆØ[™Y]\ÎˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİHH×CBˆØ[™Y]\Ëœ™\Ù\™PØ\XÚ]JZ[ŠÛ˜\ÚİË˜Ûİ[›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ÊJCBƒBˆ]›İÈH]J
CBˆ›Üˆ˜]ÔÛ˜\Úİ[ˆÛ˜\ÚİÈÃBˆİX\™]Û˜\ÚİHØ[š]^™Y›Ùš[TÛ˜\Úİ›Ü”™\İÜ™J˜]ÔÛ˜\Úİ›İÎˆ›İÊKBˆÙY[’QËš[œÙ\
Û˜\ÚİšY
Kš[œÙ\Y[ÙHÈÛÛ[YHCBˆØ[™Y]\Ë˜\[™
Û˜\Úİ
CBˆCBƒBˆ]^\İ[™ĞØ[™Y]RQÈHÙ]
BˆØ[™Y]\Ë›^CBˆ™š[\ˆÈ^\İ[™Ô›Ùš[RQË˜ÛÛZ[œÊ	šY
HCBˆœ™Yš^
›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ÊCBˆ›X\
šY
CBˆ
CBˆ]™]ØÛÛY\Ø\XÚ]HHX^
BˆBˆ›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ÈH
BˆYZ][™Õ[œ›Üİ\™Yš]˜]PÛÛ™šYİ\˜][ÛƒBˆÈ^\İ[™ĞØ[™Y]RQË˜Ûİ[Bˆˆ^\İ[™Ô›Ùš[RQË˜Ûİ[Bˆ
CBˆ
CBˆ˜\ˆYZ]Y™]ØÛÛY\œÈHBˆ˜\ˆYZ]YˆĞ˜XÚİ\›Ùš[TÛ˜\ÚİHH×CBˆYZ]Yœ™\Ù\™PØ\XÚ]JZ[ŠØ[™Y]\Ë˜Ûİ[›Ùš[SX[˜YÙ\‹›X^[][T›Ùš[\ÊJCBˆ›ÜˆÛ˜\Úİ[ˆØ[™Y]\ÈÃBˆYˆ^\İ[™ĞØ[™Y]RQË˜ÛÛZ[œÊÛ˜\ÚİšY
HÃBˆYZ]Y˜\[™
Û˜\Úİ
CBˆH[ÙHYˆYZ]Y™]ØÛÛY\œÈ™]ØÛÛY\Ø\XÚ]HÃBˆYZ]Y™]ØÛÛY\œÈ
ÏHCBˆYZ]Y˜\[™
Û˜\Úİ
CBˆCBˆCBˆ™]\›ˆYZ]YBˆCBƒBˆš]˜]H[˜È™\İÜ™T›Ùš[TÛ˜\ÚİÊBˆÈ˜XÚİ\ˆ˜XÚİ\]KBˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]Nˆ›ÛÛH˜[ÙKBˆ™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]Nˆ›ÛÛH˜[ÙCBˆ
HOˆš]˜]PÛÛ™šYİ\˜][Û”™\İÜ™T™\İ[ÃBˆİX\™]Û˜\ÚİÈH˜XÚİ\œ›Ùš[\Ë\Û˜\ÚİËš\Ñ[\H[ÙHÃBˆYˆ]İÛ™\ˆH˜XÚİ\˜Xİ]™T›Ùš[RQBˆİÛ™\ˆOH›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ\È˜XÚİ\ÛÈHÚ[™ÛH›Ùš[H

İÛ™\ŠJH[™Ø\È™\İÜ™Y[È
›Ùš[SX[˜YÙ\‹œÚ\™Y˜Xİ]™T›Ùš[RQ
H‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆCBˆ™]\›ˆš]˜]PÛÛ™šYİ\˜][Û”™\İÜ™T™\İ[
BˆØ\Ô™\İÜ™YˆYKBˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆ×CBˆ
CBˆCBˆ˜\ˆ^\İ[™Ô›Ùš[RQÈHÙ]URQŠ
CBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ]X[˜YÙ\ˆH›Ùš[SX[˜YÙ\‹œÚ\™YBƒBˆ^\İ[™Ô›Ùš[RQÈHX[˜YÙ\‹œ›Üİ\”İÜ™R\Ô™XYX›CBˆÈÙ]
X[˜YÙ\‹œ›Ùš[\Ë›X\
šY
JCBˆˆ×CBˆCBˆ]YZ]YÛ˜\ÚİÈHÙ[‹œ›Ùš[TÛ˜\ÚİĞYZ]Y›Ü”™\İÜ™JBˆÛ˜\ÚİËBˆ^\İ[™Ô›Ùš[RQÎˆ^\İ[™Ô›Ùš[RQËBˆYZ][™Õ[œ›Üİ\™Yš]˜]PÛÛ™šYİ\˜][Ûˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]CBˆ
CBˆYˆYZ]YÛ˜\ÚİË˜Ûİ[OHÛ˜\ÚİË˜Ûİ[ÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆYZ]Y
YZ]YÛ˜\ÚİË˜Ûİ[
HÙˆ
Û˜\ÚİË˜Ûİ[
H[š\]YK˜[Y›Ùš[HÛ˜\Úİ
ÊHÚ][ˆH›Üİ\ˆØ\‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆCBƒBˆ˜\ˆXØÙ\Y›Ùš[RQÈHÙ]URQŠ
CBˆYˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]HÃBˆXØÙ\Y›Ùš[RQÈHÙ]
YZ]YÛ˜\ÚİË›X\
šY
JCBˆH[ÙHÃBˆ\™›Ü›SÛ“XZ[•™XYÃBƒBˆXØÙ\Y›Ùš[RQÈH›Ùš[SX[˜YÙ\‹œÚ\™Y›Y\™ÙT›Ùš[\Ñœ›ÛP˜XÚİ\
BˆYZ]YÛ˜\ÚİË›X\ÃBˆ›Ùš[JBˆYˆ	šYBˆ˜[YNˆ	›˜[YKBˆ]˜]\”Ş[X›Ûˆ	˜]˜]\”Ş[X›ÛBˆ]˜]\ÛÛÜ’^ˆ	˜]˜]\ÛÛÜ’^Bˆ]˜]\”İÑ]Nˆ	˜]˜]\”İÑ]KBˆ[’\Úˆ	œ[’\ÚBˆ\ÒÚYÔ›Ùš[Nˆ	š\ÒÚYÔ›Ùš[KBˆÜ™X]Y]ˆ	˜Ü™X]Y]Bˆ[Ú[™ÙY]ˆ	œ[Ú[™ÙY]BˆÚYÑ›YĞÚ[™ÙY]ˆ	šÚYÑ›YĞÚ[™ÙY]Bˆ
CBˆCBˆ
CBƒBˆCBˆCBƒBˆ˜\ˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YHYCBˆ˜\ˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÈHÙ]URQŠ
CBˆ›ÜˆÛ˜\Úİ[ˆYZ]YÛ˜\ÚİÈÃBˆ]YHÛ˜\ÚİšYBˆ]\Õ[œ›Üİ\™YØ[›ÛšXØ[›Ùš[HH™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]CBˆ	‰ˆY^\İ[™Ô›Ùš[RQË˜ÛÛZ[œÊY
CBˆİX\™XØÙ\Y›Ùš[RQË˜ÛÛZ[œÊY
H[ÙHÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆÚÚ\Y›Ùš[H
Y
IÜÈ]NÈH›Üİ\ˆY\™ÙHY›İYZ]]‹Bˆ\Nˆ‘\œ›ÜˆƒBˆ
CBˆÛÛ[YCBˆCBƒBˆYˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KÛ˜\Úİœ›ÙÜ™\ÜÕØ\ĞØ\\™YÃBˆ›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™Y›ÙÜ™\ÜÑ]JBˆ˜XÚİ\]KœØ[š]^™Y›ÙÜ™\ÜÑ]JBˆÛ˜\Úİœ›ÙÜ™\ÜÑ]KBˆ™\Ù\š[™Ñ]šXÙSØØ[™Y™\™[˜Ù\ÎˆYCBˆ
KBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆYˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KÛ˜\Úİœ˜][™ÜÕÙ\™PØ\\™YÃBˆ\Ù\”˜][™ÓX[˜YÙ\‹œÚ\™Yœ™\İÜ™T˜][™ÜĞ[™›İ\ÊBˆ˜][™ÜÎˆ˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™ÜÊÛ˜\Úİ\Ù\”˜][™ÜÊKBˆ›İ\Îˆ˜XÚİ\]KœØ[š]^™Y\Ù\”˜][™Ó›İ\ÊÛ˜\Úİ\Ù\”˜][™Ó›İ\ÊKBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆYˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KÛ˜\Úİ˜ÛÛXİ[ÛœÕÙ\™PØ\\™YÃBˆ\™›Ü›SÛ“XZ[•™XYÃBˆXœ˜\SX[˜YÙ\‹œÚ\™Yœ™\XÙPÛÛXİ[ÛœÑ›Ü“YYXTİ]JBˆÛ˜\Úİ˜ÛÛXİ[ÛœË›X\È	ÓXœ˜\PÛÛXİ[ÛŠ
HKBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆCBˆYˆ\Û˜\Úİœ›ÙÜ™\ÜÕØ\ĞØ\\™YBˆ\Û˜\Úİœ˜][™ÜÕÙ\™PØ\\™YBˆ\Û˜\Úİ˜ÛÛXİ[ÛœÕÙ\™PØ\\™YBˆ\Û˜\Úİ˜Ø][ÙÜÕÙ\™PØ\\™YBˆ\Û˜\Úİ›X[™ØPÛÛXİ[ÛœÕÙ\™PØ\\™YBˆ\Û˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜÕØ\ĞØ\\™YBˆ\Û˜\Úİ›X[™ØPØ][ÙÜÕÙ\™PØ\\™YBˆ\Û˜\Úİ˜İ\İÛPØ][ÙÜÕÙ\™PØ\\™YÃBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ›Ùš[H
Y
H™\İÜ™YÚ]İ][œ™XYX›HÛXZ[œÈ
›ÙÜ™\ÜÏW
Û˜\Úİœ›ÙÜ™\ÜÕØ\ĞØ\\™Y
H˜][™ÜÏW
Û˜\Úİœ˜][™ÜÕÙ\™PØ\\™Y
HÛÛXİ[ÛœÏW
Û˜\Úİ˜ÛÛXİ[ÛœÕÙ\™PØ\\™Y
HØ][ÙÜÏW
Û˜\Úİ˜Ø][ÙÜÕÙ\™PØ\\™Y
H™XY\“Xœ˜\OW
Û˜\Úİ›X[™ØPÛÛXİ[ÛœÕÙ\™PØ\\™Y
H™XY\”›ÙÜ™\ÜÏW
Û˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜÕØ\ĞØ\\™Y
H™XY\Ø][ÙÜÏW
Û˜\Úİ›X[™ØPØ][ÙÜÕÙ\™PØ\\™Y
H™XY\İ\İÛPØ][ÙÜÏW
Û˜\Úİ˜İ\İÛPØ][ÙÜÕÙ\™PØ\\™Y
JNÈH\İ[˜][ÛˆÙY\È]ÈİÛˆÛÜH‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆCBˆYˆ\™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KBˆÛ˜\Úİ˜Ø][ÙÜÕÙ\™PØ\\™YÃBˆØ][ÙÓX[˜YÙ\‹œÚ\™Yœ™\XÙPØ][ÙÜÑ›Ü“YYXTİ]JÛ˜\Úİ˜Ø][ÙÜË›Ü”›Ùš[NˆY
CBˆCBˆYˆÛ˜\Úİ˜XÚÙ\”İ]UØ\ĞØ\\™YBˆ
Z\Õ[œ›Üİ\™YØ[›ÛšXØ[›Ùš[CBˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™Y
HÃBˆ˜\ˆ˜XÚÙ\”İ]UØ\Ô™\İÜ™YH˜[ÙCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆ˜XÚÙ\”İ]UØ\Ô™\İÜ™YH˜XÚÙ\“X[˜YÙ\‹œÚ\™Y˜\T™\İÜ™Y˜XÚÙ\”İ]JBˆÛ˜\Úİ˜XÚÙ\”İ]KBˆ›Ü”›Ùš[NˆYBˆÜ™Y[X[Ğ[™›Üİ\\™P]]Üš]]]™NƒBˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YBˆ\›Z]Õ[œ›Üİ\™Y›Ùš[Nˆ\Õ[œ›Üİ\™YØ[›ÛšXØ[›Ùš[CBˆ
CBˆCBˆYˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YBˆ]˜XÚÙ\”İ]UØ\Ô™\İÜ™YÃBˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH˜[ÙCBˆH[ÙHYˆÛ˜\Úİ˜XÚÙ\Ü™Y[X[Ğ[™›Üİ\•Ù\™PØ\\™YBˆ˜XÚÙ\”İ]UØ\Ô™\İÜ™YÃBˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQËš[œÙ\
Y
CBˆCBˆCBƒBˆ]İÜ™HH›Ùš[TÙ][™ÜÔİÜ™KœÚ\™YœİÜ™J›ÜˆY
CBƒBˆYˆ\Õ[œ›Üİ\™YØ[›ÛšXØ[›Ùš[HÃBˆYˆÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HOHš[ÃBˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH™\İÜ™T›Ùš[T™XY\ÛÛ™šYİ\˜][ÛŠBˆÛ˜\ÚİBˆ[ÎˆİÜ™KBˆ›Ùš[RQˆYBˆ\›Z]Õ[œ›Üİ\™Y›Ùš[NˆYCBˆ
H	‰ˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆCBˆÛÛ[YCBˆCBƒBˆYˆÛ˜\ÚİœÙX\˜Ú\İÜKØ\ĞØ\\™Y\Û˜\ÚİœÙX\˜Ú\İÜKœ]Y\šY\Ëš\Ñ[\KBˆ]ÙX\˜Ú\İÜQ]HHOÈ”ÓÓ‘[˜ÛÙ\Š
K™[˜ÛÙJÛ˜\ÚİœÙX\˜Ú\İÜKœ]Y\šY\ÊHÃBˆİÜ™KœÙ]
ÙX\˜Ú\İÜQ]K›Ü’Ù^NˆœÙX\˜Ú\İÜHŠCBˆCBˆ]™\Ù\™\Ó]š[Ôİ]Q›Ü•\Ñ\İ[˜][ÛˆH™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]CBˆ	‰ˆ^\İ[™Ô›Ùš[RQË˜ÛÛZ[œÊY
CBˆ	‰ˆ
T›Ùš[TÙ][™ÜÔİÜ™KœÚ\™\ÔÙ\šXÙ\ÃBˆYOH›Ùš[SX[˜YÙ\‹™Y˜][›Ùš[RQ
CBˆ]™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH™\İÜ™T›Ùš[TÛİ\˜Ù\ÊBˆÛ˜\ÚİBˆ[ÎˆİÜ™KBˆ›Ùš[RQˆYBˆ™\Ù\š[™Ñ]šXÙSØØ[]š[ĞÛİYİ]Nˆ™\Ù\™\Ó]š[Ôİ]Q›Ü•\Ñ\İ[˜][ÛƒBˆ
CBˆYˆÛ˜\Úİœ™XY\”š]˜]PÛİYÛÛ™šYİ\˜][Û‘]HOHš[Bˆ\™XY\ÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YÃBˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YH˜[ÙCBˆCBƒBˆ˜\ˆ\YYÙ][™ĞÛİ[HBˆ›Üˆ
Ù^K]JH[ˆÛ˜\ÚİœÙ][™ÜÈÚ\™HÙ[‹˜Ø\œšY\Ô›Ùš[TØÛÜYÙ][™ÊÙ^JHÃBˆYˆ™\Ù\š[™ĞØ[›ÛšXØ[YYXTİ]KBˆYYXTİ]TÙ][™Ô™YÚ\İKœØÛÜJ›ÜˆÙ^JHOHš[ÃBˆÛÛ[YCBˆCBˆİX\™\YYÙ][™ĞÛİ[Ù[‹›X^[][T›Ùš[TÙ][™ÒÙ^\È[ÙHÈœ™XZÈCBˆİX\™]˜[YHHÙ[‹˜[Y]Y˜XÚİ\Ù][™Õ˜[YJBˆœ›ÛNˆ]KBˆ›Ü’Ù^NˆÙ^CBˆ
H[ÙHÈÛÛ[YHCBˆİÜ™KœÙ]
˜[YK›Ü’Ù^NˆÙ^JCBˆ\YYÙ][™ĞÛİ[
ÏHCBˆCBˆÚYˆ[ÜÊ“ÔÊCBˆ\™›Ü›SÛ“XZ[•™XYÃBˆYˆÛ˜\Úİ›X[™ØPÛÛXİ[ÛœÕÙ\™PØ\\™YÃBˆX[™ØSXœ˜\SX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™YÛÛXİ[ÛœÊBˆÛ˜\Úİ›X[™ØPÛÛXİ[ÛœË›X\ÃBˆX[™ØSXœ˜\PÛÛXİ[ÛŠBˆYˆ	šYBˆ˜[YNˆ	›˜[YKBˆ][\Îˆ	š][\ËBˆ\ØÜš\[Ûˆ	™\ØÜš\[ÛƒBˆ
CBˆKBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆYˆÛ˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜÕØ\ĞØ\\™YÃBˆX[™ØT™XY[™Ô›ÙÜ™\ÜÓX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™Y›ÙÜ™\ÜÊBˆÛ˜\Úİ›X[™ØT™XY[™Ô›ÙÜ™\ÜËœ™YXÙJ[ÎˆÒ[ˆX[™ØT›ÙÜ™\Ü×J
JHÈ™\İ[[H[ƒBˆİX\™]Ù^HH[
[KšÙ^JH[ÙHÈ™]\›ˆCBˆ™\İ[ÚÙ^WHH[K˜[YCBˆKBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆYˆÛ˜\Úİ›X[™ØPØ][ÙÜÕÙ\™PØ\\™YÃBˆX[™ØPØ][ÙÓX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™YØ][ÙÜÊÛ˜\Úİ›X[™ØPØ][ÙÜË›Ü”›Ùš[NˆY
CBˆCBˆYˆÛ˜\Úİ˜İ\İÛPØ][ÙÜÕÙ\™PØ\\™YÃBˆØ[™[İ\İÛPØ][ÙÓX[˜YÙ\‹œÚ\™Y˜\T™\İÜ™YØ][ÙÜÊBˆÛ˜\Úİ˜İ\İÛPØ][ÙÜËBˆ›Ü”›Ùš[NˆYBˆ
CBˆCBˆCBˆÙ[™YƒBˆCBˆÙÙÙ\‹œÚ\™Y›ÙÊBˆ˜XÚİ\X[˜YÙ\ˆ™\İÜ™Y
YZ]YÛ˜\ÚİË™š[\ˆÈXØÙ\Y›Ùš[RQË˜ÛÛZ[œÊ	šY
HK˜Ûİ[
HÙˆ
Û˜\ÚİË˜Ûİ[
H›Ùš[\Èœ›ÛHH˜XÚİ\‹Bˆ\Nˆ’[™›ÈƒBˆ
CBˆ™]\›ˆš]˜]PÛÛ™šYİ\˜][Û”™\İÜ™T™\İ[
BˆØ\Ô™\İÜ™Yˆš]˜]PÛÛ™šYİ\˜][Û•Ø\Ô™\İÜ™YBˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÎˆ]]Üš]]]™U˜XÚÙ\”›Ùš[RQÃBˆ
CBˆCBŸCB