extends Node
## Yandex Games SDK via JavaScriptBridge. Mock in editor / desktop.

signal inited
signal pause_requested
signal resume_requested
signal rewarded_done(success: bool)
signal interstitial_done
signal cloud_loaded(data: Dictionary)

var sdk_ready: bool = false
var _web: bool = false
var _init_failed: bool = false
var _poll_attempts: int = 0
var _loading_ready_pending: bool = false
var _loading_ready_sent: bool = false
var _gameplay_requested: bool = false
var _gameplay_sent: String = "stop"
var _pending_score: int = -1
var _pending_cloud: Dictionary = {}
var _cloud_requested: bool = false
var _cloud_resolved: bool = false
var _cloud_last_sent_ms: int = -1
var _cloud_flush_scheduled: bool = false
var _ad_active: bool = false

## player.setData is rate-limited; a set end can trigger several saves within a second.
const CLOUD_MIN_INTERVAL_MS := 3000

# JavaScript callbacks must be held for as long as JavaScript can call them.
var _window: Variant
var _pause_callback: Variant
var _resume_callback: Variant
var _cloud_callback: Variant


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_web = OS.has_feature("web")
	if _web:
		_inject()
	else:
		sdk_ready = true
		inited.emit()


func _inject() -> void:
	JavaScriptBridge.eval("""
		window._kach = window._kach || {};
		window._kach.ready = false;
		window._kach.initFailed = false;
		window._kach.pause = function(){};
		window._kach.resume = function(){};
		window._kach.cloud = function(_json){};
	""", true)
	_bind_callbacks()
	JavaScriptBridge.eval("""
		(function() {
			// Ads/purchases (SDK events) and a hidden tab can overlap: pause on the first
			// reason, resume only when every reason is gone.
			var reasons = {};
			window._kach.hold = function(reason) {
				var wasHeld = Object.keys(reasons).length > 0;
				reasons[reason] = true;
				if (!wasHeld) window._kach.pause();
			};
			window._kach.release = function(reason) {
				if (!reasons[reason]) return;
				delete reasons[reason];
				if (Object.keys(reasons).length === 0) window._kach.resume();
			};
			document.addEventListener('visibilitychange', function() {
				if (document.hidden) window._kach.hold('hidden'); else window._kach.release('hidden');
			});
			if (document.hidden) window._kach.hold('hidden');
			var tries = 0;
			function fail() { window._kach.initFailed = true; }
			function boot() {
				tries += 1;
				if (window._kach.initFailed || tries > 300) { fail(); return; }
				if (typeof YaGames === 'undefined') {
					var old = document.getElementById('yandex-games-sdk');
					if (!old) {
						var script = document.createElement('script');
						script.id = 'yandex-games-sdk';
						script.src = '/sdk.js';
						script.onerror = fail;
						document.head.appendChild(script);
					}
					setTimeout(boot, 120);
					return;
				}
				YaGames.init().then(function(ysdk) {
					window.ysdk = ysdk;
					if (ysdk.on) {
						ysdk.on('game_api_pause', function(){ window._kach.hold('sdk'); });
						ysdk.on('game_api_resume', function(){ window._kach.release('sdk'); });
					}
					window._kach.ready = true;
				}).catch(fail);
			}
			boot();
		})();
	""", true)
	_poll_ready()


func _bind_callbacks() -> void:
	_window = JavaScriptBridge.get_interface("window")
	if _window == null:
		return
	_pause_callback = JavaScriptBridge.create_callback(_on_js_pause)
	_resume_callback = JavaScriptBridge.create_callback(_on_js_resume)
	_cloud_callback = JavaScriptBridge.create_callback(_on_js_cloud)
	var bridge: Variant = _window._kach
	if bridge != null:
		bridge.pause = _pause_callback
		bridge.resume = _resume_callback
		bridge.cloud = _cloud_callback


func _poll_ready() -> void:
	if not _web or sdk_ready or _init_failed:
		return
	_poll_attempts += 1
	var ready: Variant = JavaScriptBridge.eval("!!(window._kach && window._kach.ready)", true)
	var failed: Variant = JavaScriptBridge.eval("!!(window._kach && window._kach.initFailed)", true)
	if bool(ready):
		sdk_ready = true
		# Requirement 2.14: the game language follows the player's Yandex language.
		var lang: Variant = JavaScriptBridge.eval("(window.ysdk && ysdk.environment && ysdk.environment.i18n && ysdk.environment.i18n.lang) || ''", true)
		if str(lang) != "":
			Loc.set_language(str(lang))
		inited.emit()
		_flush_loading_ready()
		_sync_gameplay()
		_flush_score()
		_request_cloud()
	elif bool(failed) or _poll_attempts >= 300:
		_init_failed = true
		inited.emit()
	else:
		get_tree().create_timer(0.2).timeout.connect(_poll_ready)


func _on_js_pause(_args: Array) -> void:
	pause_requested.emit()
	# Listeners may save on pause; the main loop stops in a hidden tab, so push it out now.
	_flush_cloud(true)


func _on_js_resume(_args: Array) -> void:
	resume_requested.emit()


func _on_js_cloud(args: Array) -> void:
	var data: Dictionary = {}
	if not args.is_empty():
		var parsed: Variant = JSON.parse_string(str(args[0]))
		if parsed is Dictionary:
			data = parsed
	cloud_loaded.emit(data)
	_cloud_resolved = true
	_flush_cloud()


## LoadingAPI.ready() is a one-shot per session: title and gym both ask, only the first counts.
func loading_ready() -> void:
	if _loading_ready_sent:
		return
	_loading_ready_pending = true
	_flush_loading_ready()


func _flush_loading_ready() -> void:
	if not _web or not sdk_ready or not _loading_ready_pending:
		return
	JavaScriptBridge.eval("if(window.ysdk && window.ysdk.features && window.ysdk.features.LoadingAPI){window.ysdk.features.LoadingAPI.ready();}", true)
	_loading_ready_pending = false
	_loading_ready_sent = true


func gameplay_start() -> void:
	_gameplay_requested = true
	_sync_gameplay()


func gameplay_stop() -> void:
	_gameplay_requested = false
	_sync_gameplay()


func _sync_gameplay() -> void:
	if not _web or not sdk_ready:
		return
	var method := "start" if _gameplay_requested and not _ad_active else "stop"
	# GameplayAPI marks transitions: no stop before the first start, no repeated calls.
	if method == _gameplay_sent:
		return
	_gameplay_sent = method
	JavaScriptBridge.eval("if(window.ysdk && window.ysdk.features && window.ysdk.features.GameplayAPI){window.ysdk.features.GameplayAPI.%s();}" % method, true)


func is_ad_active() -> bool:
	return _ad_active


func _wait_for_sdk() -> bool:
	if sdk_ready:
		return true
	for _i in 100:
		if _init_failed:
			return false
		await get_tree().create_timer(0.1).timeout
		if sdk_ready:
			return true
	return false


func show_interstitial() -> void:
	if not _web:
		await get_tree().create_timer(0.35).timeout
		interstitial_done.emit()
		return
	if not await _wait_for_sdk():
		interstitial_done.emit()
		return
	_ad_active = true
	_sync_gameplay()
	JavaScriptBridge.eval("window._kach.interstitial = false;", true)
	JavaScriptBridge.eval("""
		try {
			if (window.ysdk && window.ysdk.adv) {
				window.ysdk.adv.showFullscreenAdv({
					callbacks: {
						onClose: function(){ window._kach.interstitial = true; },
						onError: function(){ window._kach.interstitial = true; }
					}
				});
			} else { window._kach.interstitial = true; }
		} catch (_error) { window._kach.interstitial = true; }
	""", true)
	# Ads can legitimately last well beyond ten seconds. Resume only after onClose.
	for _i in 1800:
		await get_tree().create_timer(0.1).timeout
		var done: Variant = JavaScriptBridge.eval("!!window._kach.interstitial", true)
		if bool(done):
			break
	JavaScriptBridge.eval("window._kach.interstitial = false;", true)
	_ad_active = false
	_sync_gameplay()
	interstitial_done.emit()


func show_rewarded() -> bool:
	if not _web:
		await get_tree().create_timer(0.4).timeout
		rewarded_done.emit(true)
		return true
	if not await _wait_for_sdk():
		rewarded_done.emit(false)
		return false
	_ad_active = true
	_sync_gameplay()
	JavaScriptBridge.eval("window._kach.reward = false; window._kach.rewardClosed = false;", true)
	JavaScriptBridge.eval("""
		try {
			if (window.ysdk && window.ysdk.adv) {
				window.ysdk.adv.showRewardedVideo({
					callbacks: {
						onRewarded: function(){ window._kach.reward = true; },
						onClose: function(){ window._kach.rewardClosed = true; },
						onError: function(){ window._kach.reward = false; window._kach.rewardClosed = true; }
					}
				});
			} else { window._kach.rewardClosed = true; }
		} catch (_error) { window._kach.reward = false; window._kach.rewardClosed = true; }
	""", true)
	var result := false
	for _i in 1800:
		await get_tree().create_timer(0.1).timeout
		var closed: Variant = JavaScriptBridge.eval("!!window._kach.rewardClosed", true)
		if bool(closed):
			result = bool(JavaScriptBridge.eval("!!window._kach.reward", true))
			break
	JavaScriptBridge.eval("window._kach.reward = false; window._kach.rewardClosed = false;", true)
	_ad_active = false
	_sync_gameplay()
	rewarded_done.emit(result)
	return result


func submit_score(score: int) -> void:
	if not _web:
		return
	_pending_score = maxi(_pending_score, score)
	_flush_score()


func _flush_score() -> void:
	if not _web or not sdk_ready or _pending_score < 0:
		return
	var score := _pending_score
	_pending_score = -1
	JavaScriptBridge.eval("""
		if (window.ysdk && window.ysdk.leaderboards) {
			var send = function(){ window.ysdk.leaderboards.setScore('mass', %d).catch(function(){}); };
			if (window.ysdk.isAvailableMethod) {
				window.ysdk.isAvailableMethod('leaderboards.setScore').then(function(ok){ if(ok) send(); }).catch(function(){});
			} else { send(); }
		}
	""" % score, true)


func cloud_save(data: Dictionary) -> void:
	if not _web:
		return
	_pending_cloud = data.duplicate(true)
	_flush_cloud()


func _on_cloud_flush_timer() -> void:
	_cloud_flush_scheduled = false
	_flush_cloud()


func _request_cloud() -> void:
	if not _web or not sdk_ready or _cloud_requested:
		return
	_cloud_requested = true
	JavaScriptBridge.eval("""
		window._kach.playerPromise = window._kach.playerPromise || window.ysdk.getPlayer({ scopes: false });
		window._kach.playerPromise
			.then(function(player){ return player.getData(); })
			.then(function(data){ window._kach.cloud(JSON.stringify(data || {})); })
			.catch(function(){ window._kach.playerPromise = null; window._kach.cloud('{}'); });
	""", true)


func _flush_cloud(force: bool = false) -> void:
	if not _web or not sdk_ready or not _cloud_resolved or _pending_cloud.is_empty():
		return
	if not force and _cloud_last_sent_ms >= 0:
		var wait_ms := _cloud_last_sent_ms + CLOUD_MIN_INTERVAL_MS - Time.get_ticks_msec()
		if wait_ms > 0:
			# Keep only the latest payload; send it once the interval has passed.
			if not _cloud_flush_scheduled:
				_cloud_flush_scheduled = true
				get_tree().create_timer(wait_ms / 1000.0).timeout.connect(_on_cloud_flush_timer)
			return
	_cloud_last_sent_ms = Time.get_ticks_msec()
	var payload := JSON.stringify(_pending_cloud)
	var payload_literal := JSON.stringify(payload)
	_pending_cloud.clear()
	JavaScriptBridge.eval("""
		window._kach.playerPromise = window._kach.playerPromise || window.ysdk.getPlayer({ scopes: false });
		window._kach.playerPromise
			.then(function(player){ return player.setData(JSON.parse(%s), true); })
			.catch(function(){ window._kach.playerPromise = null; });
	""" % payload_literal, true)
