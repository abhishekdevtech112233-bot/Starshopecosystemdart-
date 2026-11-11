Import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

// ==========================================
// CONFIGURATION & CONSTANTS
// ==========================================
const String kSupabaseUrl = "https://fzerbvhdaqifaeabdjkj.supabase.co";
const String kSupabaseAnonKey = "sb_publishable_ajo-GdO4PcqhQDTcde9m7w_Ib6kzaVM";

const String kFallbackMedical = "https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?auto=format&fit=crop&w=700&q=80";
const String kFallbackGrocery = "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=700&q=80";
const String kFallbackRetail = "https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=700&q=80";

const List<String> kFallbackSalonImages = [
  "https://images.unsplash.com/photo-1580618672591-eb180b1a973f?auto=format&fit=crop&w=700&q=80",
  "https://images.unsplash.com/photo-1560066984-138dadb4c035?auto=format&fit=crop&w=700&q=80",
  "https://images.unsplash.com/photo-1516975080661-42bceb9f0028?auto=format&fit=crop&w=700&q=80"
];

// ==========================================
// DATA MODELS
// ==========================================
class MerchantModel {
  final String id;
  final String storeName;
  final String category;
  final String address;
  final String phone;
  final String displayImage;
  final String discountText;
  final String conditionsText;
  final double? latitude;
  final double? longitude;
  final bool isOpenToday;

  MerchantModel({
    required this.id,
    required this.storeName,
    required this.category,
    required this.address,
    required this.phone,
    required this.displayImage,
    required this.discountText,
    required this.conditionsText,
    this.latitude,
    this.longitude,
    required this.isOpenToday,
  });

  factory MerchantModel.fromMap(Map<String, dynamic> map, int index) {
    final String cat = (map['category'] ?? 'SALON').toString();
    final String rawImage = (map['profile_image_url'] ?? map['image_url'] ?? map['display_image'] ?? '').toString();

    String fallback = kFallbackRetail;
    final catLower = cat.toLowerCase();
    if (catLower.contains('medical') || catLower.contains('chemist')) {
      fallback = kFallbackMedical;
    } else if (catLower.contains('grocery') || catLower.contains('kirana')) {
      fallback = kFallbackGrocery;
    } else if (catLower.contains('salon') || catLower.contains('parlor')) {
      fallback = kFallbackSalonImages[index % kFallbackSalonImages.length];
    }

    double? lat;
    double? lon;
    if (map['latitude'] != null) lat = double.tryParse(map['latitude'].toString());
    if (map['longitude'] != null) lon = double.tryParse(map['longitude'].toString());
    if (lat == null && map['location'] != null && map['location'].toString().contains(',')) {
      final parts = map['location'].toString().split(',');
      lat = double.tryParse(parts[0].trim());
      lon = double.tryParse(parts[1].trim());
    }

    return MerchantModel(
      id: map['id']?.toString() ?? UniqueKey().toString(),
      storeName: (map['shop_name'] ?? map['store_name'] ?? map['name'] ?? 'Star Merchant').toString(),
      category: cat,
      address: (map['address'] ?? map['location'] ?? 'Delhi, India').toString(),
      phone: (map['phone'] ?? map['mobile'] ?? 'Unavailable').toString(),
      displayImage: rawImage.isNotEmpty ? rawImage : fallback,
      discountText: (map['offer_text'] ?? (map['offer_details'] is Map ? map['offer_details']['discount'] : null) ?? 'Special Discount').toString(),
      conditionsText: (map['description'] ?? (map['offer_details'] is Map ? map['offer_details']['conditions'] : null) ?? 'Best rates').toString(),
      latitude: lat,
      longitude: lon,
      isOpenToday: map['is_open_today'] != false,
    );
  }
}

class ReelItemModel {
  final String id;
  final String reelId;
  final String mediaUrl;
  final String musicUrl;
  final String storeName;
  final String discount;
  final String avatar;
  final String location;
  final String distance;
  final String lat;
  final String lon;
  int ratingCount;
  int likeCount;
  bool isLikedByUser;

  ReelItemModel({
    required this.id,
    required this.reelId,
    required this.mediaUrl,
    required this.musicUrl,
    required this.storeName,
    required this.discount,
    required this.avatar,
    required this.location,
    required this.distance,
    required this.lat,
    required this.lon,
    this.ratingCount = 0,
    this.likeCount = 0,
    this.isLikedByUser = false,
  });
}

class PostItemModel {
  final String id;
  final String storeName;
  final String category;
  final String avatar;
  final String postImage;
  final String caption;
  final String distance;
  final String musicUrl;

  PostItemModel({
    required this.id,
    required this.storeName,
    required this.category,
    required this.avatar,
    required this.postImage,
    required this.caption,
    required this.distance,
    required this.musicUrl,
  });
}

class ClaimHistoryModel {
  final String rawDate;
  final String date;
  final String store;
  final String saved;

  ClaimHistoryModel({
    required this.rawDate,
    required this.date,
    required this.store,
    required this.saved,
  });

  Map<String, dynamic> toMap() => {
        'rawDate': rawDate,
        'date': date,
        'store': store,
        'saved': saved,
      };

  factory ClaimHistoryModel.fromMap(Map<String, dynamic> map) => ClaimHistoryModel(
        rawDate: map['rawDate'] ?? DateTime.now().toIso8601String(),
        date: map['date'] ?? '',
        store: map['store'] ?? '',
        saved: map['saved'] ?? '',
      );
}

// ==========================================
// APP INITIALIZATION
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  runApp(const StarShopsApp());
}

class StarShopsApp extends StatefulWidget {
  const StarShopsApp({super.key});

  @override
  State<StarShopsApp> createState() => _StarShopsAppState();
}

class _StarShopsAppState extends State<StarShopsApp> {
  bool _isHighDiscountActive = false;

  void setHighDiscount(bool active) {
    setState(() => _isHighDiscountActive = active);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STAR SHOPS',
      debugShowCheckedModeBanner: false,
      theme: _isHighDiscountActive
          ? ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF050505),
              cardColor: const Color(0xFF0A0A0A),
              primaryColor: const Color(0xFFD4AF37),
            )
          : ThemeData.light().copyWith(
              scaffoldBackgroundColor: const Color(0xFFF8F9FA),
              cardColor: Colors.white,
              primaryColor: const Color(0xFF111827),
            ),
      home: MainDeviceShell(
        isHighDiscountActive: _isHighDiscountActive,
        onToggleTheme: setHighDiscount,
      ),
    );
  }
}

// ==========================================
// MAIN DEVICE SHELL
// ==========================================
class MainDeviceShell extends StatefulWidget {
  final bool isHighDiscountActive;
  final Function(bool) onToggleTheme;

  const MainDeviceShell({
    super.key,
    required this.isHighDiscountActive,
    required this.onToggleTheme,
  });

  @override
  State<MainDeviceShell> createState() => _MainDeviceShellState();
}

class _MainDeviceShellState extends State<MainDeviceShell> {
  final supabase = Supabase.instance.client;
  int _currentTab = 0;
  String _currentLocationName = "इलाका खोज रहे हैं...";
  double? _userLat;
  double? _userLon;
  bool _isScanningLocation = false;

  String _userName = "लोड हो रहा है...";
  String _userPhone = "";
  String _deviceUuid = "";
  int _userFootprints = 0;
  int _currentSteps = 0;
  final int _targetSteps = 2000;
  List<ClaimHistoryModel> _claimHistory = [];
  List<Map<String, dynamic>> _savedDeals = [];

  List<MerchantModel> _allMerchants = [];
  List<MerchantModel> _liveStores = [];
  List<PostItemModel> _postsFeed = [];
  List<ReelItemModel> _reelsFeed = [];
  bool _isLoadingData = false;

  @override
  void initState() {
    super.initState();
    _loadLocalUserData();
    _fetchSupabaseData();
    _requestLocation();
  }

  // --- 1. LOCAL DATA & SYNC TO SUPABASE ---
  Future<void> _loadLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();

    _deviceUuid = prefs.getString('starshops_device_uuid') ?? '';
    if (_deviceUuid.isEmpty) {
      _deviceUuid = 'user_${math.Random().nextInt(9999999)}';
      await prefs.setString('starshops_device_uuid', _deviceUuid);
    }

    final savedUserJson = prefs.getString('starshops_consumer_user');
    if (savedUserJson != null) {
      final decoded = jsonDecode(savedUserJson);
      _userName = decoded['name'] ?? 'User';
      _userPhone = decoded['phone'] ?? '';
      _syncConsumerProfileToSupabase();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRegistrationDialog());
    }

    final claimsJson = prefs.getString('starshops_local_claims');
    if (claimsJson != null) {
      final List raw = jsonDecode(claimsJson);
      _claimHistory = raw.map((e) => ClaimHistoryModel.fromMap(e)).toList();
    }

    final savedDealsJson = prefs.getString('starshops_saved_deals');
    if (savedDealsJson != null) {
      final List raw = jsonDecode(savedDealsJson);
      _savedDeals = raw.cast<Map<String, dynamic>>();
    }

    _userFootprints = prefs.getInt('starshops_total_footprints') ?? 0;
    _currentSteps = prefs.getInt('star_user_steps') ?? 0;
    if (_currentSteps >= _targetSteps) {
      widget.onToggleTheme(true);
    }
    setState(() {});
  }

  Future<void> _syncConsumerProfileToSupabase() async {
    if (_deviceUuid.isEmpty) return;
    try {
      final existing = await supabase.from('consumers').select('id').eq('device_uuid', _deviceUuid).maybeSingle();
      final data = {
        'device_uuid': _deviceUuid,
        'name': _userName,
        'phone': _userPhone,
        'total_footprints': _userFootprints,
        'unlocked_high_discount': widget.isHighDiscountActive,
      };

      if (existing != null) {
        await supabase.from('consumers').update(data).eq('id', existing['id']);
      } else {
        await supabase.from('consumers').insert(data);
      }
    } catch (e) {
      debugPrint("Consumer sync error: $e");
    }
  }

  // --- 2. SUPABASE FULL DATA FETCH ---
  Future<void> _fetchSupabaseData() async {
    setState(() => _isLoadingData = true);

    try {
      final merchantData = await supabase.from('merchants').select('*');
      final postsData = await supabase.from('merchant_posts').select('*');
      final reelsData = await supabase.from('merchant_reels').select('*');

      _allMerchants = (merchantData as List).asMap().entries.map((entry) {
        return MerchantModel.fromMap(entry.value, entry.key);
      }).toList();

      _liveStores = _allMerchants.where((m) => m.isOpenToday).toList();

      _postsFeed = (postsData as List).map((p) {
        final mId = (p['merchant_id'] ?? '').toString();
        final merchant = _allMerchants.firstWhere((m) => m.id == mId, orElse: () => _allMerchants.first);
        return PostItemModel(
          id: merchant.id,
          storeName: merchant.storeName,
          category: merchant.category,
          avatar: merchant.displayImage,
          postImage: (p['post_image_url'] ?? p['image_url'] ?? '').toString(),
          caption: (p['caption'] ?? merchant.discountText).toString(),
          distance: merchant.address,
          musicUrl: (p['music_url'] ?? p['audio_url'] ?? '').toString(),
        );
      }).where((post) => post.postImage.isNotEmpty).toList();

      _reelsFeed.clear();
      for (var r in (reelsData as List)) {
        final reelId = r['id'].toString();
        final mId = (r['merchant_id'] ?? '').toString();
        final merchant = _allMerchants.firstWhere((m) => m.id == mId, orElse: () => _allMerchants.first);
        final videoUrl = (r['reel_url'] ?? r['video_url'] ?? '').toString();

        if (videoUrl.isNotEmpty) {
          final likeCountRes = await supabase.from('likes').select('id').eq('reel_id', reelId);
          final int totalLikes = (likeCountRes as List).length;

          bool userLiked = false;
          if (_deviceUuid.isNotEmpty) {
            final userLikeCheck = await supabase.from('likes').select('id').eq('reel_id', reelId).eq('user_id', _deviceUuid).maybeSingle();
            userLiked = userLikeCheck != null;
          }

          _reelsFeed.add(ReelItemModel(
            id: merchant.id,
            reelId: reelId,
            mediaUrl: videoUrl,
            musicUrl: (r['music_url'] ?? r['audio_url'] ?? '').toString(),
            storeName: merchant.storeName,
            discount: (r['caption'] ?? merchant.discountText).toString(),
            avatar: merchant.displayImage,
            location: merchant.address,
            distance: merchant.address,
            lat: merchant.latitude?.toString() ?? '',
            lon: merchant.longitude?.toString() ?? '',
            likeCount: totalLikes,
            ratingCount: totalLikes,
            isLikedByUser: userLiked,
          ));
        }
      }

      _applyLocationSorting();
    } catch (e) {
      debugPrint("Supabase Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  // --- 3. SUPABASE ANALYTICS & INTERACTION LOGIC ---
  Future<void> _toggleLikeInSupabase(ReelItemModel reel) async {
    try {
      if (reel.isLikedByUser) {
        await supabase.from('likes').delete().eq('reel_id', reel.reelId).eq('user_id', _deviceUuid);
        reel.isLikedByUser = false;
        reel.likeCount = math.max(0, reel.likeCount - 1);
        reel.ratingCount = reel.likeCount;
      } else {
        await supabase.from('likes').insert({'reel_id': reel.reelId, 'user_id': _deviceUuid});
        reel.isLikedByUser = true;
        reel.likeCount += 1;
        reel.ratingCount = reel.likeCount;
      }
      setState(() {});
    } catch (e) {
      debugPrint("Like toggle error: $e");
    }
  }

  Future<void> _recordReelView(ReelItemModel reel) async {
    try {
      await supabase.from('merchant_views').insert({
        'merchant_id': reel.id,
        'reel_id': reel.reelId,
        'user_device_id': _deviceUuid,
        'view_count': 1,
      });

      await supabase.from('merchant_footprint_analytics').insert({
        'merchant_id': reel.id,
        'reel_id': reel.reelId,
        'user_device_id': _deviceUuid,
        'watched_at': DateTime.now().toIso8601String(),
        'map_clicked': false,
        'conversion_status': 'viewed'
      });
    } catch (e) {
      debugPrint("Analytics view record error: $e");
    }
  }

  Future<void> _recordMapClick(String merchantId, String reelId) async {
    try {
      await supabase.from('merchant_footprint_analytics').insert({
        'merchant_id': merchantId,
        'reel_id': reelId,
        'user_device_id': _deviceUuid,
        'map_clicked': true,
        'map_opened_at': DateTime.now().toIso8601String(),
        'conversion_status': 'map_opened'
      });
    } catch (e) {
      debugPrint("Map click record error: $e");
    }
  }

  // --- 4. REVERSE GEOCODING (BIGDATACLOUD) ---
  Future<void> _requestLocation() async {
    setState(() => _isScanningLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );
        _userLat = pos.latitude;
        _userLon = pos.longitude;

        // BigDataCloud API Reverse Geocoding
        final url = Uri.parse("https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$_userLat&longitude=$_userLon&localityLanguage=hi");
        final res = await http.get(url);
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final locality = data['locality'] ?? data['suburb'] ?? data['city'] ?? "दिल्ली";
          _currentLocationName = "$locality, दिल्ली";
        } else {
          _currentLocationName = "रोहिणी, दिल्ली";
        }
      } else {
        _currentLocationName = "बेगमपुर, दिल्ली";
      }
    } catch (e) {
      _currentLocationName = "बेगमपुर, दिल्ली";
    } finally {
      _isScanningLocation = false;
      _applyLocationSorting();
      if (mounted) setState(() {});
    }
  }

  void _applyLocationSorting() {
    if (_userLat != null && _userLon != null) {
      _liveStores.sort((a, b) {
        if (a.latitude == null || a.longitude == null) return 1;
        if (b.latitude == null || b.longitude == null) return -1;
        final distA = Geolocator.distanceBetween(_userLat!, _userLon!, a.latitude!, a.longitude!);
        final distB = Geolocator.distanceBetween(_userLat!, _userLon!, b.latitude!, b.longitude!);
        return distA.compareTo(distB);
      });
    }
  }

  // --- 5. PIN VERIFICATION DIALOG ---
  void _showPinVerificationDialog(MerchantModel store) {
    final pinController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Claim: ${store.storeName}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text("दुकानदार के काउंटर से 4-अंकों का पिन पूछकर दर्ज करें", style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(counterText: "", filled: true),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("रद्द करें"))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                        onPressed: isVerifying
                            ? null
                            : () async {
                                final pin = pinController.text.trim();
                                if (pin.length != 4) return;
                                setDialogState(() => isVerifying = true);

                                try {
                                  final res = await supabase.rpc('secure_verify_claim', params: {
                                    'p_merchant_id': store.id,
                                    'p_pin': pin,
                                    'p_device_id': _deviceUuid,
                                    'p_store_name': store.storeName,
                                    'p_claim_title': "${store.storeName} - ${store.discountText}",
                                  });

                                  if (mounted) Navigator.pop(ctx);
                                  if (res != null && res['success'] == true) {
                                    _processSuccessfulClaim(store);
                                  } else {
                                    _showMsg("विफल ❌", res?['message'] ?? "गलत पिन दर्ज किया गया है!");
                                  }
                                } catch (e) {
                                  if (mounted) Navigator.pop(ctx);
                                  _showMsg("त्रुटि", "सर्वर से पिन वेरीफाई नहीं हो सका: $e");
                                }
                              },
                        child: isVerifying
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text("वेरीफ़ाई करें"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _processSuccessfulClaim(MerchantModel store) async {
    final now = DateTime.now();
    final claim = ClaimHistoryModel(
      rawDate: now.toIso8601String(),
      date: "${now.day}/${now.month}/${now.year}",
      store: store.storeName,
      saved: store.discountText,
    );

    _claimHistory.insert(0, claim);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('starshops_local_claims', jsonEncode(_claimHistory.map((e) => e.toMap()).toList()));

    _currentSteps += 500;
    _userFootprints += 500;
    if (_currentSteps >= _targetSteps && !widget.isHighDiscountActive) {
      _currentSteps = _targetSteps;
      widget.onToggleTheme(true);
    }

    await prefs.setInt('star_user_steps', _currentSteps);
    await prefs.setInt('starshops_total_footprints', _userFootprints);

    _syncConsumerProfileToSupabase();
    setState(() {});
    _showMsg("सफलता! 🎉", "ऑफर सफलतापूर्वक क्लेम कर लिया गया है!");
  }

  void _showRegistrationDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("वेलकम तू Star Shops ⭐", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "पूरा नाम", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: "मोबाइल नंबर", border: OutlineInputBorder(), counterText: "")),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                  onPressed: () async {
                    if (nameCtrl.text.trim().length < 2 || phoneCtrl.text.trim().length < 10) return;
                    _userName = nameCtrl.text.trim();
                    _userPhone = phoneCtrl.text.trim();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('starshops_consumer_user', jsonEncode({'name': _userName, 'phone': _userPhone}));
                    _syncConsumerProfileToSupabase();
                    if (mounted) Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: const Text("शुरू करें 🚀"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showMsg(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ठीक है"))],
      ),
    );
  }

  // --- 6. SAVED REELS & DEALS VAULT MODAL ---
  void _openSavedDealsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("⭐ सेव्ड डील्स & वॉल्ट", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Text("⚠️ चेतावनी: यह सेव की गई रील और ऑफर रात 12:00 बजे गायब हो जाएंगे!", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            Expanded(
              child: _savedDeals.isEmpty
                  ? const Center(child: Text("कोई सेव की गई डील नहीं मिली।", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _savedDeals.length,
                      itemBuilder: (ctx, i) {
                        final item = _savedDeals[i];
                        return ListTile(
                          leading: const Icon(Icons.lock, color: Colors.amber),
                          title: Text(item['store'] ?? 'Store', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(item['offer'] ?? ''),
                          trailing: const Text("आज रात 12 बजे तक", style: TextStyle(color: Colors.red, fontSize: 10)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentTab == 1
          ? null
          : AppBar(
              backgroundColor: Theme.of(context).cardColor,
              elevation: 0.5,
              title: const Text("STAR SHOPS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: _openSavedDealsModal,
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text(_isScanningLocation ? "Locating..." : _currentLocationName, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                )
              ],
            ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          StoresTab(
            stores: _liveStores,
            isLoading: _isLoadingData,
            onRefresh: _fetchSupabaseData,
            onClaim: _showPinVerificationDialog,
            currentSteps: _currentSteps,
            targetSteps: _targetSteps,
          ),
          ReelsTab(
            reels: _reelsFeed,
            onLikeToggle: _toggleLikeInSupabase,
            onReelWatched: _recordReelView,
            onMapOpened: _recordMapClick,
          ),
          PostsTab(posts: _postsFeed, onRefresh: _fetchSupabaseData),
          AlertsTab(stores: _liveStores),
          ProfileTab(
            userName: _userName,
            userPhone: _userPhone,
            userFootprints: _userFootprints,
            totalClaims: _claimHistory.length,
            claimHistory: _claimHistory,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).cardColor,
        selectedItemColor: widget.isHighDiscountActive ? const Color(0xFFD4AF37) : Colors.black87,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.storefront), label: "Stores"),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_fill), label: "Reels"),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_sharp), label: "Posts"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Alerts"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

// ==========================================
// TABS & ADVANCED WIDGETS
// ==========================================

// --- TAB 1: STORES ---
class StoresTab extends StatelessWidget {
  final List<MerchantModel> stores;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final Function(MerchantModel) onClaim;
  final int currentSteps;
  final int targetSteps;

  const StoresTab({
    super.key,
    required this.stores,
    required this.isLoading,
    required this.onRefresh,
    required this.onClaim,
    required this.currentSteps,
    required this.targetSteps,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (stores.isEmpty) return const Center(child: Text("No stores available."));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: stores.length,
        itemBuilder: (ctx, i) {
          final s = stores[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: CachedNetworkImage(imageUrl: s.displayImage, height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(s.address.split(',').first, style: const TextStyle(color: Colors.amber, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(s.discountText, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                          onPressed: () => onClaim(s),
                          child: const Text("Claim via PIN"),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- TAB 2: REELS TAB ---
class ReelsTab extends StatefulWidget {
  final List<ReelItemModel> reels;
  final Function(ReelItemModel) onLikeToggle;
  final Function(ReelItemModel) onReelWatched;
  final Function(String, String) onMapOpened;

  const ReelsTab({
    super.key,
    required this.reels,
    required this.onLikeToggle,
    required this.onReelWatched,
    required this.onMapOpened,
  });

  @override
  State<ReelsTab> createState() => _ReelsTabState();
}

class _ReelsTabState extends State<ReelsTab> {
  int _focusedIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.reels.isEmpty) return const Center(child: Text("No reels available", style: TextStyle(color: Colors.white)));

    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: widget.reels.length,
      onPageChanged: (index) {
        setState(() => _focusedIndex = index);
        widget.onReelWatched(widget.reels[index]);
      },
      itemBuilder: (ctx, i) => SingleReelPlayer(
        reel: widget.reels[i],
        isActive: i == _focusedIndex,
        onLikeToggle: () => widget.onLikeToggle(widget.reels[i]),
        onMapClick: () => widget.onMapOpened(widget.reels[i].id, widget.reels[i].reelId),
      ),
    );
  }
}

class SingleReelPlayer extends StatefulWidget {
  final ReelItemModel reel;
  final bool isActive;
  final VoidCallback onLikeToggle;
  final VoidCallback onMapClick;

  const SingleReelPlayer({
    super.key,
    required this.reel,
    required this.isActive,
    required this.onLikeToggle,
    required this.onMapClick,
  });

  @override
  State<SingleReelPlayer> createState() => _SingleReelPlayerState();
}

class _SingleReelPlayerState extends State<SingleReelPlayer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.reel.mediaUrl))
      ..initialize().then((_) {
        if (widget.isActive) {
          _controller?.play();
          _controller?.setLooping(true);
        }
        if (mounted) setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant SingleReelPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null && _controller!.value.isInitialized)
          Center(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)))
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned(
          right: 14,
          bottom: 50,
          child: Column(
            children: [
              IconButton(
                icon: Icon(widget.reel.isLikedByUser ? Icons.star : Icons.star_border, color: Colors.white, size: 36),
                onPressed: widget.onLikeToggle,
              ),
              Text("${widget.reel.likeCount}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white, size: 28),
                onPressed: () => Share.share("Watch this offer: ${widget.reel.mediaUrl}"),
              )
            ],
          ),
        ),
        Positioned(
          left: 14,
          bottom: 30,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.reel.storeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(widget.reel.discount, style: const TextStyle(color: Colors.amber, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  widget.onMapClick();
                  final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(widget.reel.location)}");
                  if (await canLaunchUrl(url)) await launchUrl(url);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text("${widget.reel.distance} (Open Maps)", style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

// --- TAB 3: POSTS ---
class PostsTab extends StatelessWidget {
  final List<PostItemModel> posts;
  final Future<void> Function() onRefresh;

  const PostsTab({super.key, required this.posts, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: posts.length,
        itemBuilder: (ctx, i) {
          final p = posts[i];
          return Card(
            margin: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: CircleAvatar(backgroundImage: CachedNetworkImageProvider(p.avatar)),
                  title: Text(p.storeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                CachedNetworkImage(imageUrl: p.postImage, width: double.infinity, fit: BoxFit.cover),
                Padding(padding: const EdgeInsets.all(12), child: Text(p.caption)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- TAB 4: ALERTS ---
class AlertsTab extends StatelessWidget {
  final List<MerchantModel> stores;
  const AlertsTab({super.key, required this.stores});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: stores.length,
      itemBuilder: (ctx, i) => Card(
        child: ListTile(
          leading: const Text("⚡", style: TextStyle(fontSize: 24)),
          title: Text("${stores[i].storeName} is Live!"),
          subtitle: Text(stores[i].discountText),
        ),
      ),
    );
  }
}

// --- TAB 5: PROFILE & SMART CALCULATOR ---
class ProfileTab extends StatefulWidget {
  final String userName;
  final String userPhone;
  final int userFootprints;
  final int totalClaims;
  final List<ClaimHistoryModel> claimHistory;

  const ProfileTab({
    super.key,
    required this.userName,
    required this.userPhone,
    required this.userFootprints,
    required this.totalClaims,
    required this.claimHistory,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _calcExpression = "0";

  void _onCalcPress(String btn) {
    setState(() {
      if (btn == 'C') {
        _calcExpression = '0';
      } else if (btn == '⌫') {
        _calcExpression = _calcExpression.length > 1 ? _calcExpression.substring(0, _calcExpression.length - 1) : '0';
      } else if (btn == '=') {
        try {
          String sanitized = _calcExpression.replaceAll('×', '*').replaceAll('÷', '/');
          Parser p = Parser();
          Expression exp = p.parse(sanitized);
          ContextModel cm = ContextModel();
          double eval = exp.evaluate(EvaluationType.REAL, cm);
          _calcExpression = eval.toStringAsFixed(eval.truncateToDouble() == eval ? 0 : 2);
        } catch (e) {
          _calcExpression = 'Error';
        }
      } else {
        if (_calcExpression == '0') {
          _calcExpression = btn;
        } else {
          _calcExpression += btn;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Color(0xFF111827),
                    child: Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(widget.userPhone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [Text("${widget.totalClaims}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)), const Text("Claims")]),
                      Column(children: [Text("${widget.userFootprints}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)), const Text("Footprints")]),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // SMART CALCULATOR (पूर्ण रूप से शामिल)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text("Smart Savings Calculator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                    child: Text(_calcExpression, textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  _buildCalcGrid(),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCalcGrid() {
    final buttons = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['0', '00', '.', '=']
    ];

    return Column(
      children: buttons.map((row) {
        return Row(
          children: row.map((b) {
            final isOp = ['÷', '×', '-', '+', '%', '='].contains(b);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOp ? const Color(0xFFFFFBEB) : Theme.of(context).cardColor,
                    foregroundColor: isOp ? const Color(0xFFB45309) : Colors.black87,
                    elevation: 0.5,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _onCalcPress(b),
                  child: Text(b, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
} 
