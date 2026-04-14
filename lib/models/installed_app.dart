class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
    required this.isLaunchable,
    required this.category,
    this.isUnknownCategory = false,
    required this.versionName,
    required this.versionCode,
    required this.installerPackage,
    required this.installedTime,
    required this.updatedTime,
    required this.lastSeenAt,
  });

  final String packageName;
  final String appName;
  final bool isSystemApp;
  final bool isLaunchable;
  final String category;
  /// True when store category could not be mapped to a known label ([normalizeInstalledAppCategory] → `unknown`).
  final bool isUnknownCategory;
  final String versionName;
  final int versionCode;
  final String installerPackage;
  final int? installedTime;
  final int? updatedTime;
  final int lastSeenAt;

  static const Set<String> _knownRelevantExactPackages = {
    'com.whatsapp',
    'com.whatsapp.w4b',
    'com.whatsapp.business',
    'com.instagram.android',
    'com.facebook.katana',
    'com.facebook.orca',
    'com.facebook.lite',
    'com.snapchat.android',
    'org.telegram.messenger',
    'org.thunderdog.challegram',
    'com.discord',
    'com.twitter.android',
    'com.twitter.twidere',
    'com.threads.android',
    'com.reddit.frontpage',
    'com.zhiliaoapp.musically',
    'com.google.android.youtube',
    'com.google.android.apps.youtube.music',
    'com.netflix.mediaclient',
    'com.disney.disneyplus',
    'com.amazon.avod.thirdpartyclient',
    'tv.twitch.android.app',
    'com.spotify.music',
    'com.roblox.client',
    'com.ss.android.ugc.trill',
  };

  static const List<String> _knownRelevantPackagePrefixes = [
    'com.instagram.',
    'com.facebook.',
    'com.google.android.youtube',
    'com.zhiliaoapp.',
    'org.telegram.',
    'com.discord',
    'com.snapchat.',
    'com.twitter.',
    'com.reddit.',
    'tv.twitch.',
    'com.spotify.',
    'com.roblox.',
    'com.supercell.',
    'com.king.',
    'com.moonactive.',
    'com.epicgames.',
    'com.activision.',
    'com.ea.',
    'com.miniclip.',
    'com.playrix.',
    'com.google.android.apps.youtube',
    'com.netflix.',
    'com.discord.',
    'com.whatsapp.',
    'com.spotify.',
  ];

  static const Set<String> _knownExcludedExactPackages = {
    'com.example.genet_final',
    'com.android.settings',
    'com.android.systemui',
    'com.google.android.gms',
    'com.google.android.gsf',
    'com.google.android.gsf.login',
    'com.google.android.packageinstaller',
    'com.android.packageinstaller',
    'com.android.permissioncontroller',
    'com.google.android.permissioncontroller',
    'com.android.printspooler',
    'com.android.vending',
    'com.google.android.gm',
    'com.google.android.googlequicksearchbox',
    'com.google.android.projection.gearhead',
    'com.google.android.safetycore',
    'com.google.android.apps.maps',
    'com.waze',
    'com.google.android.apps.photos',
    'com.android.dialer',
    'com.google.android.dialer',
    'com.android.contacts',
    'com.google.android.contacts',
    'com.google.android.calculator',
    'com.android.calculator2',
    'com.google.android.calendar',
    'com.google.android.deskclock',
    'com.sec.android.app.myfiles',
    'com.google.android.apps.nbu.files',
    'com.google.android.apps.docs',
    'com.google.android.apps.docs.editors.docs',
    'com.google.android.apps.docs.editors.sheets',
    'com.google.android.apps.docs.editors.slides',
    'com.google.android.apps.docs.editors.drive',
    'com.microsoft.office.word',
    'com.microsoft.office.excel',
    'com.microsoft.office.powerpoint',
  };

  static const List<String> _knownExcludedPackageTerms = [
    'inputmethod',
    'keyboard',
    'launcher',
    'documentsui',
    'filemanager',
    'filemanager',
    'packageinstaller',
    'permissioncontroller',
    'print',
    'updater',
    'service',
    'provider',
    'assistant',
    'devicecare',
    'devicepolicy',
    'verifier',
    'safetycore',
    'gearhead',
    'androidauto',
  ];

  static const List<String> _knownExcludedNameTerms = [
    'gmail',
    'mail',
    'maps',
    'waze',
    'phone',
    'contacts',
    'camera',
    'gallery',
    'photos',
    'files',
    'settings',
    'clock',
    'calculator',
    'calendar',
    'android auto',
    'key verifier',
    'safetycore',
    'launcher',
    'keyboard',
    'play store',
    'google app',
    'assistant',
    'drive',
    'docs',
    'sheets',
    'slides',
    'word',
    'excel',
    'powerpoint',
    'maps go',
    'google maps',
    'my files',
  ];

  static const List<String> _knownRelevantNameTerms = [
    'whatsapp',
    'instagram',
    'facebook',
    'messenger',
    'telegram',
    'snapchat',
    'tiktok',
    'discord',
    'twitter',
    'threads',
    'reddit',
    'youtube',
    'netflix',
    'spotify',
    'twitch',
    'disney',
    'prime video',
    'roblox',
    'brawl stars',
    'pubg',
    'fortnite',
    'clash of clans',
  ];

  static const Set<String> _relevantCategories = {
    'game',
    'social',
    'audio',
    'video',
  };

  static const Set<String> _storeInstallerPackages = {
    'com.android.vending',
    'com.sec.android.app.samsungapps',
    'com.amazon.venezia',
    'com.huawei.appmarket',
    'com.xiaomi.market',
    'com.oppo.market',
    'com.heytap.market',
    'com.transsion.phoenix',
  };

  static const List<String> _auditPackages = [
    'youtube',
    'instagram',
    'tiktok',
    'chrome',
    'whatsapp',
    'spotify',
    'netflix',
  ];

  /// WebView / Trichrome — not a standalone browser for parental listing.
  static const Set<String> _webViewEnginePackages = {
    'com.google.android.webview',
    'com.android.webview',
    'com.google.android.trichromelibrary',
  };

  static const Set<String> _knownBrowserExactPackages = {
    'com.android.chrome',
    'com.android.browser',
    'com.chrome.beta',
    'com.chrome.dev',
    'com.chrome.canary',
    'com.google.android.apps.chrome',
    'org.mozilla.firefox',
    'org.mozilla.fennec',
    'org.mozilla.firefox_beta',
    'com.opera.browser',
    'com.opera.mini.native',
    'com.opera.gx',
    'com.microsoft.emmx',
    'com.sec.android.app.sbrowser',
    'com.brave.browser',
    'com.duckduckgo.mobile.android',
    'org.torproject.torbrowser',
    'com.vivaldi.browser',
    'com.kiwibrowser.browser',
    'com.yandex.browser',
    'com.uc.browser.en',
    'com.ucmobile.intl',
    'com.ucmobile.lite',
    'com.ucmobile.x86',
    'com.qwant.mobilenext',
    'com.ecosia.android',
    'mark.via.gp',
    'com.apus.browser',
    'com.cake.browser',
    'com.stoutner.privacybrowser.standard',
    'org.bromite.bromite',
    'pure.lite.browser',
    'com.pure.browser.plus',
    'com.huawei.browser',
    'com.huawei.android.browser',
    'com.mi.global.browser',
    'com.heytap.browser',
    'com.coloros.browser',
    'com.oneplus.browser',
    'com.vivo.browser',
    'com.oplus.browser',
    'com.alohamobile.browser',
    'com.aloha.browser',
    'org.mozilla.focus',
  };

  static const List<String> _knownBrowserPackagePrefixes = [
    'com.chrome.',
    'org.mozilla.',
    'com.opera.',
    'com.microsoft.emmx',
    'com.vivaldi.',
    'com.brave.',
    'com.duckduckgo.',
    'com.kiwibrowser',
    'com.yandex.browser',
    'com.sec.android.app.sbrowser',
    'com.huawei.browser',
    'com.alohamobile.',
    'com.aloha.',
    'com.pure.browser',
    'com.uc.browser',
    'com.ucmobile.',
  ];

  /// Default SMS/MMS UIs parents often want to manage alongside chat apps.
  static const Set<String> _stockSmsUiExactPackages = {
    'com.google.android.apps.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
  };

  /// Facebook / Meta components that are not the consumer social apps.
  static const Set<String> _socialPackageFalsePositiveExact = {
    'com.facebook.system',
    'com.facebook.appmanager',
    'com.facebook.services',
  };

  static const List<String> _socialPackageFalsePositiveTerms = [
    'facebook.services',
    'facebook.appmanager',
    'facebook.system',
    'socialplugin',
    'social.analytics',
  ];

  static const Set<String> _knownSocialExactPackages = {
    'com.instagram.android',
    'com.instagram.lite',
    'com.facebook.katana',
    'com.facebook.lite',
    'com.facebook.mlite',
    'com.facebook.orca',
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.ss.android.ugc.aweme',
    'com.snapchat.android',
    'com.twitter.android',
    'com.twitter.twidere',
    'com.threads.android',
    'com.pinterest',
    'com.reddit.frontpage',
    'com.linkedin.android',
  };

  static const List<String> _knownSocialPackagePrefixes = [
    'com.instagram.',
    'com.zhiliaoapp.',
    'com.ss.android.ugc.',
    'com.reddit.',
    'com.linkedin.',
    'com.threads.',
    'com.snapchat.android',
  ];

  /// OEM / Meta helpers — not a user-facing social row for the blocklist.
  static bool socialPackageLooksLikeFalsePositive(String packageLower) {
    if (_socialPackageFalsePositiveExact.contains(packageLower)) return true;
    for (final t in _socialPackageFalsePositiveTerms) {
      if (packageLower.contains(t)) return true;
    }
    return false;
  }

  /// Strong package match for major social / short-video / X-Twitter family apps.
  static bool isKnownSocialPackage(String packageLower) {
    if (socialPackageLooksLikeFalsePositive(packageLower)) return false;
    if (_knownSocialExactPackages.contains(packageLower)) return true;
    if (_knownSocialPackagePrefixes.any(packageLower.startsWith)) return true;
    if (packageLower == 'com.pinterest' || packageLower.startsWith('com.pinterest.')) {
      return true;
    }
    if (packageLower == 'com.twitter.android' ||
        packageLower.startsWith('com.twitter.android.')) {
      return true;
    }
    const segments = <String>[
      'instagram',
      'tiktok',
      'musically',
      '.trill',
      'snapchat',
      'pinterest',
      'reddit',
      'linkedin',
    ];
    for (final s in segments) {
      if (packageLower.contains(s)) return true;
    }
    if (packageLower.contains('threads') && packageLower.contains('android')) return true;
    if (packageLower.contains('facebook.katana') ||
        packageLower.contains('facebook.lite') ||
        packageLower.contains('facebook.mlite')) {
      return true;
    }
    return false;
  }

  /// Display-name signals; callers should still apply [looksLikeTechnicalOrUtilityNoise].
  static bool looksLikeSocialAppName(String appName) {
    var n = appName.trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return false;
    const needles = <String>[
      'instagram',
      'facebook',
      'tiktok',
      'snapchat',
      'twitter',
      'threads',
      'pinterest',
      'reddit',
      'linkedin',
    ];
    for (final s in needles) {
      if (n.contains(s)) return true;
    }
    if (n.contains('formerly twitter')) return true;
    if (RegExp(r'\bsocial\b').hasMatch(n)) return true;
    return false;
  }

  /// Package or name match for parent relevance; browsers excluded. Name path still needs noise filter at call site.
  static bool isApprovedSocialApp(String packageLower, String appName) {
    if (isKnownBrowserPackage(packageLower)) return false;
    if (socialPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return true;
    return looksLikeSocialAppName(appName);
  }

  /// OEM / local players / editors — not streaming catalog apps.
  static const List<String> _videoPackageFalsePositiveTerms = [
    'videolan',
    'org.videolan',
    'mxplayer',
    'mxtech',
    'mx.player',
    'videoplayer',
    'video.player',
    'gallery3d',
    'android.gallery',
    'google.android.apps.photos',
    'media.storage',
    'mediaprovider',
    'mediaserver',
    'videocompress',
    'videoeditor',
    'movieeditor',
    'screenrecorder',
    'sec.android.app.videoplayer',
    'miui.video',
    'himovie',
    'videolist',
  ];

  static bool videoPackageLooksLikeFalsePositive(String packageLower) {
    for (final t in _videoPackageFalsePositiveTerms) {
      if (packageLower.contains(t)) return true;
    }
    return false;
  }

  static const Set<String> _knownVideoExactPackages = {
    'com.google.android.youtube',
    'com.google.android.apps.youtube.music',
    'com.google.android.youtube.tv',
    'com.netflix.mediaclient',
    'com.amazon.avod.thirdpartyclient',
    'com.amazon.avod',
    'com.disney.disneyplus',
    'tv.twitch.android.app',
    'com.hbo.hbonow',
    'com.hbo.hbomax',
    'com.wbd.stream',
    'com.hotstar.android',
    'in.startv.hotstar',
    'com.vimeo.android.viewer',
    'com.vimeo.android.vimeo',
    'tv.plex.vulcan',
    'tv.plex.livingroom',
    'com.dailymotion.dailymotion',
  };

  static const List<String> _knownVideoPackagePrefixes = [
    'com.google.android.youtube',
    'com.google.android.apps.youtube',
    'com.netflix.',
    'tv.twitch.',
    'com.amazon.avod',
    'com.amazon.video',
    'com.primevideo.',
    'com.disney.',
    'com.hbo.',
    'com.wbd.',
    'com.hotstar',
    'in.startv.hotstar',
    'com.vimeo.',
    'tv.plex.',
    'dailymotion.',
  ];

  /// Strong package match for major streaming / VOD clients (not local players).
  static bool isKnownVideoApp(String packageLower) {
    if (videoPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (_knownVideoExactPackages.contains(packageLower)) return true;
    if (_knownVideoPackagePrefixes.any(packageLower.startsWith)) return true;
    const segments = <String>[
      'youtube',
      'netflix',
      'twitch',
      'disney',
      'primevideo',
      'amazonvideo',
      'hbomax',
      'hbo.max',
      'hbonow',
      'hotstar',
      'vimeo',
      'dailymotion',
      'crunchyroll',
    ];
    for (final s in segments) {
      if (packageLower.contains(s)) return true;
    }
    return false;
  }

  /// Display-name signals for streaming brands; avoid generic "video player" / VLC-style names.
  static bool looksLikeVideoAppName(String appName) {
    var n = appName.trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return false;
    if (n.contains('mx player') || n.contains('vlc') || n.contains('videolan')) return false;
    if (RegExp(r'\bvideo player\b').hasMatch(n) &&
        !n.contains('prime video') &&
        !n.contains('primevideo') &&
        !n.contains('netflix')) {
      return false;
    }
    const needles = <String>[
      'amazon prime video',
      'prime video',
      'disney+',
      'disney plus',
      'hbo max',
      'youtube',
      'netflix',
      'twitch',
      'vimeo',
      'plex',
      'dailymotion',
      'hotstar',
      'paramount+',
      'paramount plus',
      'crunchyroll',
    ];
    for (final s in needles) {
      if (n.contains(s)) return true;
    }
    return false;
  }

  static bool isApprovedVideoApp(String packageLower, String appName) {
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (videoPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownVideoApp(packageLower)) return true;
    return looksLikeVideoAppName(appName);
  }

  /// Play Games, engines/SDKs, OEM hubs, boosters, emulators — not end-user games for the blocklist.
  static const List<String> _gamePackageFalsePositiveTerms = [
    'com.google.android.play.games',
    'google.android.play.games',
    'play.games',
    'unity3d',
    'unrealengine',
    'epicgames.unreal',
    'gamebooster',
    'game.boost',
    'game_boost',
    'gamelauncher',
    'gaminghub',
    'gamehub',
    'gameservice',
    'gamespace',
    'gamemode',
    'gameturbo',
    'gameassistant',
    'gameplugins',
    'gameoverlay',
    'gamesdk',
    'gameservices',
    'gameanalytics',
    'coloros.gamespace',
    'oxygenos.gamespace',
    'realme.gamespace',
    'oneplus.gamespace',
    'miui.gameturbo',
    'samsung.android.game',
    'lg.world.game',
    'bluestacks',
    'noxplayer',
    'ldplayer',
    'lemuroid',
  ];

  static bool gamePackageLooksLikeFalsePositive(String packageLower) {
    for (final t in _gamePackageFalsePositiveTerms) {
      if (packageLower.contains(t)) return true;
    }
    return false;
  }

  /// Small set of widely used mobile game package ids (exact + tight vendor prefixes only).
  static const Set<String> _knownGameExactPackages = {
    'com.roblox.client',
    'com.tencent.ig',
    'com.pubg.krmobile',
    'com.tencent.tmgp.pubgmhd',
    'com.supercell.clashofclans',
    'com.supercell.clashroyale',
    'com.supercell.brawlstars',
    'com.mojang.minecraftpe',
    'com.king.candycrushsaga',
    'com.sybo.subway',
    'com.miniclip.eightballpool',
    'com.activision.callofduty.shooter',
    'com.garena.game.codm',
    'com.ea.gp.fifamobile',
    'com.ea.fifaultimate',
  };

  static const List<String> _knownGamePackagePrefixes = [
    'com.supercell.',
    'com.roblox.',
    'com.mojang.',
    'com.sybo.',
    'com.tencent.ig',
    'com.activision.callofduty.',
  ];

  /// Strong package match for real mobile games (not Play Games / boosters / hubs).
  static bool isKnownGamePackage(String packageLower) {
    if (gamePackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower)) return false;
    if (_knownGameExactPackages.contains(packageLower)) return true;
    return _knownGamePackagePrefixes.any(packageLower.startsWith);
  }

  /// Branded game titles only — no generic "game" / "play" / "arcade" alone.
  static bool looksLikeGameAppName(String appName) {
    var n = appName.trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return false;
    const needles = <String>[
      'roblox',
      'pubg',
      'clash royale',
      'clash of clans',
      'brawl stars',
      'minecraft',
      'candy crush',
      'subway surfers',
      '8 ball pool',
      'call of duty',
      'cod mobile',
      'fifa',
      'ea sports fc',
    ];
    for (final s in needles) {
      if (n.contains(s)) return true;
    }
    return false;
  }

  static bool isApprovedGameApp(String packageLower, String appName) {
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower)) return false;
    if (gamePackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownGamePackage(packageLower)) return true;
    return looksLikeGameAppName(appName);
  }

  /// RCS/IMS/carrier SMS plumbing, backup/migration, OEM plugins — not standalone chat apps.
  static const List<String> _messagingPackageFalsePositiveTerms = [
    'google.android.ims',
    'rcsservice',
    'ims.service',
    'imsprovider',
    'carrier.services',
    'cellbroadcast',
    'smsbackup',
    'sms.restore',
    'smsrestore',
    'backuptrans',
    'mms.service',
    'telephonyui',
    'conversation.plugin',
    'messagesuite',
    'msg.sdk',
    'chat.sdk',
    'pushservice',
    'companiondevice',
  ];

  static bool messagingPackageLooksLikeFalsePositive(String packageLower) {
    for (final t in _messagingPackageFalsePositiveTerms) {
      if (packageLower.contains(t)) return true;
    }
    return false;
  }

  /// Small set of widely used chat app package ids (exact + tight prefixes; no broad "message" segments).
  static const Set<String> _knownMessagingExactPackages = {
    'com.whatsapp',
    'com.whatsapp.w4b',
    'com.whatsapp.business',
    'org.telegram.messenger',
    'org.thunderdog.challegram',
    'org.thoughtcrime.securesms',
    'com.viber.voip',
    'jp.naver.line.android',
    'com.tencent.mm',
  };

  static const List<String> _knownMessagingPackagePrefixes = [
    'com.whatsapp.',
    'org.telegram.',
    'com.viber.',
    'jp.naver.line.',
    'com.tencent.mm',
  ];

  /// Strong package match for major chat apps (not stock SMS UIs — those use [isStockSmsUiPackage]).
  static bool isKnownMessagingPackage(String packageLower) {
    if (isStockSmsUiPackage(packageLower)) return false;
    if (messagingPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower)) return false;
    if (isKnownGamePackage(packageLower)) return false;
    if (_knownMessagingExactPackages.contains(packageLower)) return true;
    return _knownMessagingPackagePrefixes.any(packageLower.startsWith);
  }

  /// Branded chat titles only — no generic "message" / "chat" / "talk" / loose "messenger".
  static bool looksLikeMessagingAppName(String appName) {
    var n = appName.trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return false;
    if (n == 'line') {
      return true;
    }
    if (n.contains('messenger') &&
        !n.contains('whatsapp') &&
        !n.contains('telegram') &&
        !n.contains('signal')) {
      return false;
    }
    const phraseNeedles = <String>[
      'whatsapp messenger',
      'telegram messenger',
      'signal private messenger',
    ];
    for (final p in phraseNeedles) {
      if (n.contains(p)) return true;
    }
    const needles = <String>[
      'whatsapp',
      'telegram',
      'signal',
      'viber',
      'wechat',
    ];
    for (final s in needles) {
      if (n.contains(s)) return true;
    }
    return false;
  }

  static bool isApprovedMessagingApp(String packageLower, String appName) {
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower)) return false;
    if (isKnownGamePackage(packageLower)) return false;
    if (messagingPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownMessagingPackage(packageLower)) return true;
    return looksLikeMessagingAppName(appName);
  }

  /// OEM equalizers, ringtone UIs, FX — not streaming music catalog apps.
  static const List<String> _musicPackageFalsePositiveTerms = [
    'musicfx',
    'equalizer',
    'ringtone',
    'soundpicker',
    'audiopolicy',
    'voiceprint',
    'voicerecognition',
    'karaoke.factory',
    'headsetsettings',
    'audioservice',
  ];

  static bool musicPackageLooksLikeFalsePositive(String packageLower) {
    for (final t in _musicPackageFalsePositiveTerms) {
      if (packageLower.contains(t)) return true;
    }
    return false;
  }

  /// Streaming / radio brands (exact + tight prefixes).
  static const Set<String> _knownMusicExactPackages = {
    'com.spotify.music',
    'com.google.android.apps.youtube.music',
    'deezer.android.app',
    'com.amazon.mp3',
    'com.apple.android.music',
    'com.aspiro.tidal',
    'com.soundcloud.android',
    'com.audiomack',
    'com.afmobi.boomplayer',
    'com.transsnet.boomplay',
    'com.pandora.android',
  };

  static const List<String> _knownMusicPackagePrefixes = [
    'com.spotify.music.',
    'com.soundcloud.',
    'deezer.android.',
    'com.amazon.mp3',
    'com.pandora.',
  ];

  /// Strong package match for major music streaming apps (not system audio helpers).
  static bool isKnownMusicPackage(String packageLower) {
    if (musicPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower) &&
        packageLower != 'com.google.android.apps.youtube.music') {
      return false;
    }
    if (isKnownGamePackage(packageLower)) return false;
    if (isKnownMessagingPackage(packageLower)) return false;
    if (_knownMusicExactPackages.contains(packageLower)) return true;
    return _knownMusicPackagePrefixes.any(packageLower.startsWith);
  }

  /// Branded streaming titles only — no standalone "music" / "audio" / "player".
  static bool looksLikeMusicAppName(String appName) {
    var n = appName.trim().toLowerCase();
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return false;
    const phraseNeedles = <String>[
      'youtube music',
      'apple music',
      'amazon music',
    ];
    for (final p in phraseNeedles) {
      if (n.contains(p)) return true;
    }
    const needles = <String>[
      'spotify',
      'deezer',
      'tidal',
      'soundcloud',
      'audiomack',
      'boomplay',
      'pandora',
    ];
    for (final s in needles) {
      if (n.contains(s)) return true;
    }
    return false;
  }

  static bool isApprovedMusicApp(String packageLower, String appName) {
    if (isKnownBrowserPackage(packageLower)) return false;
    if (isKnownSocialPackage(packageLower)) return false;
    if (isKnownVideoApp(packageLower) &&
        packageLower != 'com.google.android.apps.youtube.music') {
      return false;
    }
    if (isKnownGamePackage(packageLower)) return false;
    if (isKnownMessagingPackage(packageLower)) return false;
    if (musicPackageLooksLikeFalsePositive(packageLower)) return false;
    if (isKnownMusicPackage(packageLower)) return true;
    return looksLikeMusicAppName(appName);
  }

  /// WebView / Trichrome — exclude from parent blocklist as standalone browsers.
  static bool isWebViewEnginePackage(String packageLower) {
    return _webViewEnginePackages.contains(packageLower);
  }

  /// WebView / Trichrome / Custom Tabs helpers — not a user-facing browser row.
  static bool browserPackageLooksLikeEngineOrHelper(String packageLower) {
    if (_webViewEnginePackages.contains(packageLower)) return true;
    if (packageLower.contains('webview')) return true;
    if (packageLower.contains('trichrome')) return true;
    if (packageLower.contains('chromelibrary')) return true;
    if (packageLower.contains('customtabs')) return true;
    if (packageLower.contains('custom.tabs')) return true;
    return false;
  }

  /// Strong package/prefix match for real browsers (after [browserPackageLooksLikeEngineOrHelper] is false).
  static bool isKnownBrowserPackage(String packageLower) {
    if (browserPackageLooksLikeEngineOrHelper(packageLower)) return false;
    for (final id in _knownBrowserExactPackages) {
      if (id.toLowerCase() == packageLower) return true;
    }
    return _knownBrowserPackagePrefixes.any(packageLower.startsWith);
  }

  /// Legacy name; same as [isKnownBrowserPackage].
  static bool isLikelyBrowserPackage(String packageLower) {
    return isKnownBrowserPackage(packageLower);
  }

  static bool isStockSmsUiPackage(String packageLower) {
    return _stockSmsUiExactPackages.contains(packageLower);
  }

  static InstalledApp? fromNativeMap(Map<String, dynamic> map) {
    final packageName = (map['package'] as String? ?? '').trim();
    if (packageName.isEmpty) return null;
    final appName = (map['name'] as String? ?? '').trim();
    return InstalledApp(
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      category: (map['category'] as String? ?? '').trim().toLowerCase(),
      isUnknownCategory: map['isUnknownCategory'] == true,
      versionName: (map['versionName'] as String? ?? '').trim(),
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      installerPackage: (map['installerPackage'] as String? ?? '').trim(),
      installedTime: (map['installedTime'] as num?)?.toInt(),
      updatedTime: (map['updatedTime'] as num?)?.toInt(),
      lastSeenAt:
          (map['lastSeenAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  static InstalledApp? fromBackendMap(Map<String, dynamic> map) {
    final packageName = (map['packageName'] as String? ?? '').trim();
    if (packageName.isEmpty) return null;
    final appName = (map['appName'] as String? ?? '').trim();
    return InstalledApp(
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      category: (map['category'] as String? ?? '').trim().toLowerCase(),
      isUnknownCategory: map['isUnknownCategory'] == true,
      versionName: (map['versionName'] as String? ?? '').trim(),
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      installerPackage: (map['installerPackage'] as String? ?? '').trim(),
      installedTime: (map['installedTime'] as num?)?.toInt(),
      updatedTime: (map['updatedTime'] as num?)?.toInt(),
      lastSeenAt:
          (map['lastSeenAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toBackendMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'isSystemApp': isSystemApp,
      'isLaunchable': isLaunchable,
      'category': category,
      'isUnknownCategory': isUnknownCategory,
      'versionName': versionName,
      'versionCode': versionCode,
      'installerPackage': installerPackage,
      'installedTime': installedTime,
      'updatedTime': updatedTime,
      'lastSeenAt': lastSeenAt,
    };
  }

  String fingerprintPart() =>
      '$packageName|$appName|$isSystemApp|$isLaunchable|$category|$isUnknownCategory|$versionName|$versionCode|$installerPackage|${installedTime ?? 0}|${updatedTime ?? 0}';

  bool get installedFromStore {
    return _storeInstallerPackages.contains(installerPackage.toLowerCase());
  }

  bool get clearlyExcluded {
    final packageLower = packageName.toLowerCase();
    final nameLower = appName.toLowerCase();
    if (_knownExcludedExactPackages.contains(packageLower)) return true;
    if (_knownExcludedPackageTerms.any(packageLower.contains)) return true;
    if (_knownExcludedNameTerms.any(nameLower.contains)) return true;
    return false;
  }

  bool get clearlyIncluded {
    final packageLower = packageName.toLowerCase();
    final nameLower = appName.toLowerCase();
    if (_knownRelevantExactPackages.contains(packageLower)) return true;
    if (_knownRelevantPackagePrefixes.any(packageLower.startsWith)) return true;
    if (_knownRelevantNameTerms.any(nameLower.contains)) return true;
    return false;
  }

  bool get excludedBySystemMetadata {
    if (!isLaunchable) return true;
    final p = packageName.toLowerCase();
    if (_webViewEnginePackages.contains(p)) return true;
    if (isLikelyBrowserPackage(p)) return false;
    if (isStockSmsUiPackage(p)) return false;
    if (isSystemApp) return true;
    return false;
  }

  bool get relevantByCategory {
    return _relevantCategories.contains(category);
  }

  InstalledApp copyWith({
    String? packageName,
    String? appName,
    bool? isSystemApp,
    bool? isLaunchable,
    String? category,
    bool? isUnknownCategory,
    String? versionName,
    int? versionCode,
    String? installerPackage,
    int? installedTime,
    int? updatedTime,
    int? lastSeenAt,
  }) {
    return InstalledApp(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      isLaunchable: isLaunchable ?? this.isLaunchable,
      category: category ?? this.category,
      isUnknownCategory: isUnknownCategory ?? this.isUnknownCategory,
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      installerPackage: installerPackage ?? this.installerPackage,
      installedTime: installedTime ?? this.installedTime,
      updatedTime: updatedTime ?? this.updatedTime,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  bool isRelevantForParent() {
    if (!isLaunchable) return false;
    final p = packageName.toLowerCase();
    if (_webViewEnginePackages.contains(p)) return false;
    if (isLikelyBrowserPackage(p)) return true;
    if (isStockSmsUiPackage(p)) return true;

    if (excludedBySystemMetadata) return false;
    if (clearlyExcluded) return false;
    if (relevantByCategory) return true;
    if (clearlyIncluded) return true;
    return false;
  }

  bool get relevantForParent {
    return isRelevantForParent();
  }

  bool get shouldAuditClassification {
    final packageLower = packageName.toLowerCase();
    return _auditPackages.any(packageLower.contains);
  }

  static List<InstalledApp> fromNativeList(
    List<Map<String, dynamic>> raw,
  ) {
    final byPackage = <String, InstalledApp>{};
    for (final item in raw) {
      final app = InstalledApp.fromNativeMap(item);
      if (app == null) continue;
      byPackage[app.packageName] = app;
    }
    final list = byPackage.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }

  static List<InstalledApp> classifyAppsForParentalControl(
    List<InstalledApp> rawApps,
  ) {
    final byPackage = <String, InstalledApp>{};
    for (final app in rawApps) {
      if (!app.isRelevantForParent()) {
        continue;
      }
      byPackage[app.packageName] = app;
    }
    final list = byPackage.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }
}

class InstalledAppsInventory {
  const InstalledAppsInventory({
    required this.apps,
    required this.appCount,
    required this.rawInstalledAppCount,
    required this.appsHash,
    required this.lastSyncAt,
    required this.lastSyncTrigger,
  });

  final List<InstalledApp> apps;
  final int appCount;
  final int rawInstalledAppCount;
  final String appsHash;
  final int? lastSyncAt;
  final String lastSyncTrigger;
}
