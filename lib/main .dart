
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrimeYardBootstrapApp());
}

class PrimeYardBootstrapApp extends StatefulWidget {
  const PrimeYardBootstrapApp({super.key});
  @override
  State<PrimeYardBootstrapApp> createState() => _PrimeYardBootstrapAppState();
}

class _PrimeYardBootstrapAppState extends State<PrimeYardBootstrapApp> {
  late final Future<_BootPayload> _future = _init();
  Future<_BootPayload> _init() async {
    String? err;
    try { await BackendService.initialize().timeout(const Duration(seconds: 12)); } catch (e) { err = 'Firebase init failed: $e'; }
    return _BootPayload(session: await AppSession.load(), error: err);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<_BootPayload>(
    future: _future,
    builder: (ctx, snap) {
      if (!snap.hasData) return MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(backgroundColor: Pal.deep, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/logo-mark.png', width: 100), const SizedBox(height: 20), const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 14), const Text('Starting…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]))));
      return PrimeYardApp(session: snap.data!.session, startupError: snap.data!.error);
    },
  );
}
class _BootPayload { final AppSession session; final String? error; _BootPayload({required this.session, this.error}); }

// ══════════════════════════════════════════════════════════════════════════════
// FIREBASE CONFIG
// ══════════════════════════════════════════════════════════════════════════════

class Cfg {
  static const opts = FirebaseOptions(
    apiKey: 'AIzaSyAf0ziL9na5z7CPodC33T1SjQVBOCXUFCg',
    appId: '1:1063126418476:android:d42f77528438d22ac7bd89',
    messagingSenderId: '1063126418476',
    projectId: 'primeyard-521ea',
    storageBucket: 'primeyard-521ea.firebasestorage.app',
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PALETTE
// ══════════════════════════════════════════════════════════════════════════════

class Pal {
  static const green   = Color(0xFF1A6B30);
  static const deep    = Color(0xFF0D3B1A);
  static const soft    = Color(0xFF2F8A4B);
  static const gold    = Color(0xFFF2B632);
  static const cream   = Color(0xFFF5F1E8);
  static const white   = Colors.white;
  static const text    = Color(0xFF171717);
  static const muted   = Color(0xFF6D665D);
  static const border  = Color(0xFFE6DED0);
  static const danger  = Color(0xFFC62828);
  static const infoBg  = Color(0xFFE3F2FD);
  static const infoFg  = Color(0xFF1565C0);
}

// ══════════════════════════════════════════════════════════════════════════════
// SESSION
// ══════════════════════════════════════════════════════════════════════════════

class AppSession {
  final bool loggedIn;
  final String id, username, displayName, role;
  const AppSession({this.loggedIn=false,this.id='',this.username='',this.displayName='',this.role=''});
  bool get isAdmin => role=='admin'||role=='master_admin';
  bool get isMaster => role=='master_admin';
  bool get isSupervisor => role=='supervisor';
  bool get isWorker => role=='worker';
  static Future<AppSession> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSession(loggedIn:p.getBool('li')??false,id:p.getString('uid')??'',username:p.getString('un')??'',displayName:p.getString('dn')??'',role:p.getString('role')??'');
  }
  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('li',loggedIn); await p.setString('uid',id); await p.setString('un',username); await p.setString('dn',displayName); await p.setString('role',role);
  }
  static Future<void> clear() async => (await SharedPreferences.getInstance()).clear();
}

// ══════════════════════════════════════════════════════════════════════════════
// WORKSPACE STATE
// ══════════════════════════════════════════════════════════════════════════════

class WS {
  final List<dynamic> clients,invoices,jobs,emps,quotes,equipment,checkLogs,clockEntries,users;
  final String schedDate;
  final DateTime? updatedAt;
  final Map<String,dynamic> pricingRules;

  const WS({required this.clients,required this.invoices,required this.jobs,required this.emps,required this.quotes,required this.equipment,required this.checkLogs,required this.clockEntries,required this.users,required this.schedDate,this.updatedAt,required this.pricingRules});

  factory WS.empty() => WS(clients:[],invoices:[],jobs:[],emps:[],quotes:[],equipment:[],checkLogs:[],clockEntries:[],users:[],schedDate:_today(),pricingRules:defaultPricing);

  static Map<String,dynamic> get defaultPricing => {
    'mowing':   {'label':'Lawn Mowing',     'rate':0.15,'unit':'sqm'},
    'edging':   {'label':'Edging & Trim',   'rate':0.05,'unit':'sqm'},
    'hedges':   {'label':'Hedge Trimming',  'rate':250.0,'unit':'hour'},
    'cleanup':  {'label':'Full Cleanup',    'rate':0.25,'unit':'sqm'},
    'fertilize':{'label':'Fertilization',   'rate':0.18,'unit':'sqm'},
    'weed':     {'label':'Weed Removal',    'rate':0.20,'unit':'sqm'},
    'irrigation':{'label':'Irrigation Check','rate':350.0,'unit':'visit'},
    'paving':   {'label':'Paving/Paths',    'rate':0.30,'unit':'sqm'},
  };

  factory WS.fromMap(Map<String,dynamic>? m) {
    final d = m??{};
    return WS(
      clients:   List.from(d['clients']??[]),
      invoices:  List.from(d['invoices']??[]),
      jobs:      List.from(d['jobs']??[]),
      emps:      List.from(d['emps']??[]),
      quotes:    List.from(d['quotes']??[]),
      equipment: List.from(d['equipment']??[]),
      checkLogs: List.from(d['checkLogs']??[]),
      clockEntries:List.from(d['clockEntries']??[]),
      users:     List.from(d['users']??[]),
      schedDate: (d['schedDate']??_today()).toString(),
      updatedAt: d['updatedAt'] is Timestamp ? (d['updatedAt'] as Timestamp).toDate() : (d['updatedAt'] is String ? DateTime.tryParse(d['updatedAt']) : null),
      pricingRules: d['pricingRules'] is Map ? Map<String,dynamic>.from(d['pricingRules'] as Map) : defaultPricing,
    );
  }

  Map<String,dynamic> toMap() => {
    'clients':clients,'invoices':invoices,'jobs':jobs,'emps':emps,'quotes':quotes,
    'equipment':equipment,'checkLogs':checkLogs,'clockEntries':clockEntries,'users':users,
    'schedDate':schedDate,'pricingRules':pricingRules,
  };

  WS copyWith({List<dynamic>? clients,List<dynamic>? invoices,List<dynamic>? jobs,List<dynamic>? emps,List<dynamic>? quotes,List<dynamic>? equipment,List<dynamic>? checkLogs,List<dynamic>? clockEntries,List<dynamic>? users,String? schedDate,Map<String,dynamic>? pricingRules}) =>
    WS(clients:clients??this.clients,invoices:invoices??this.invoices,jobs:jobs??this.jobs,emps:emps??this.emps,quotes:quotes??this.quotes,equipment:equipment??this.equipment,checkLogs:checkLogs??this.checkLogs,clockEntries:clockEntries??this.clockEntries,users:users??this.users,schedDate:schedDate??this.schedDate,pricingRules:pricingRules??this.pricingRules,updatedAt:updatedAt);

  static Map<String,dynamic> get defaultPricing => WS.defaultPricing;
}

// ══════════════════════════════════════════════════════════════════════════════
// BACKEND SERVICE
// ══════════════════════════════════════════════════════════════════════════════

class BackendBootstrap {
  final WS state; final String? error; final bool hasRemoteData;
  const BackendBootstrap({required this.state,this.error,required this.hasRemoteData});
}

class BackendService {
  static final _auth = fb.FirebaseAuth.instance;
  static final _doc  = FirebaseFirestore.instance.collection('primeyard').doc('sharedState');
  static final _photos = FirebaseFirestore.instance.collection('primeyard_photos');

  static Future<void> initialize() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: Cfg.opts);
  }
  static Future<void> _ensureAuth() async {
    await initialize();
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
    if (_auth.currentUser == null) await _auth.authStateChanges().firstWhere((u) => u != null);
  }

  // ── Cache ──────────────────────────────────────────────────────────────────
  static Future<void> _cacheState(Map<String,dynamic> d) async => (await SharedPreferences.getInstance()).setString('wsc', jsonEncode(_safe(d)));
  static Future<void> _cacheUsers(List u) async => (await SharedPreferences.getInstance()).setString('usc', jsonEncode(_safe(u)));
  static Future<WS> _loadCached() async {
    final raw = (await SharedPreferences.getInstance()).getString('wsc');
    if (raw==null||raw.isEmpty) return WS.empty();
    try { return WS.fromMap(jsonDecode(raw) as Map<String,dynamic>); } catch(_) { return WS.empty(); }
  }
  static Future<List<Map<String,dynamic>>> _loadCachedUsers() async {
    final raw = (await SharedPreferences.getInstance()).getString('usc');
    if (raw==null||raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList(); } catch(_) { return []; }
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────
  static Future<BackendBootstrap> bootstrap() async {
    try {
      await _ensureAuth();
      final snap = await _doc.get(const GetOptions(source: Source.serverAndCache));
      if (!snap.exists) { final c=await _loadCached(); return BackendBootstrap(state:c,hasRemoteData:false,error:'No Firestore document found.'); }
      final d = Map<String,dynamic>.from(snap.data()??{});
      await _cacheState(d); await _cacheUsers(List.from(d['users']??[]));
      final st = WS.fromMap(d);
      return BackendBootstrap(state:st,hasRemoteData:st.users.isNotEmpty||st.clients.isNotEmpty||st.jobs.isNotEmpty);
    } on fb.FirebaseAuthException catch(e) { final c=await _loadCached(); return BackendBootstrap(state:c,hasRemoteData:false,error:'[auth/${e.code}] ${e.message}'); }
      on FirebaseException catch(e) { final c=await _loadCached(); return BackendBootstrap(state:c,hasRemoteData:false,error:'[firebase/${e.code}] ${e.message}'); }
      catch(e) { final c=await _loadCached(); return BackendBootstrap(state:c,hasRemoteData:false,error:e.toString()); }
  }

  // ── Stream ─────────────────────────────────────────────────────────────────
  static Stream<WS> streamState() async* {
    try {
      await _ensureAuth();
      yield* _doc.snapshots().asyncMap((s) async {
        if (!s.exists) return await _loadCached();
        final d = Map<String,dynamic>.from(s.data()??{});
        await _cacheState(d); await _cacheUsers(List.from(d['users']??[]));
        return WS.fromMap(d);
      });
    } catch(_) { yield await _loadCached(); }
  }

  // ── Get / Save ─────────────────────────────────────────────────────────────
  static Future<WS> getState() async {
    try {
      await _ensureAuth();
      final s = await _doc.get(const GetOptions(source: Source.serverAndCache));
      if (!s.exists) return await _loadCached();
      final d = Map<String,dynamic>.from(s.data()??{});
      await _cacheState(d); await _cacheUsers(List.from(d['users']??[]));
      return WS.fromMap(d);
    } catch(_) { return await _loadCached(); }
  }

  static Future<void> saveState(WS st, {String by='app'}) async {
    await _ensureAuth();
    final d = {...st.toMap(),'updatedAt':FieldValue.serverTimestamp(),'updatedBy':by};
    await _doc.set(d, SetOptions(merge:true));
    await _cacheState(st.toMap()); await _cacheUsers(st.users);
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  static Future<Map<String,dynamic>?> login(String username, String password) async {
    final u = username.toLowerCase(); final h = _hash(password);
    Future<Map<String,dynamic>?> check(List users) async {
      for (final e in users) { if (e is Map) { final row=Map<String,dynamic>.from(e); if((row['username']??'').toString().toLowerCase()==u&&(row['passwordHash']??'')==h) return row; } }
      return null;
    }
    final st = await getState();
    return await check(st.users) ?? await check(await _loadCachedUsers());
  }

  // ── Photos (stored in Firestore, not Storage) ──────────────────────────────
  // This avoids Firebase Storage security rule issues entirely.
  // Each photo is stored as a separate Firestore document.
  static Future<String?> savePhoto(String jobId, String type, File file) async {
    try {
      await _ensureAuth();
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final ref = _photos.doc();
      await ref.set({'jobId':jobId,'type':type,'data':b64,'by':_auth.currentUser?.uid??'','ts':FieldValue.serverTimestamp()});
      return ref.id;
    } catch(e) { return null; }
  }

  static Future<Uint8List?> loadPhoto(String photoId) async {
    try {
      final doc = await _photos.doc(photoId).get();
      if (!doc.exists) return null;
      final b64 = doc.data()?['data'] as String?;
      return b64 != null ? base64Decode(b64) : null;
    } catch(_) { return null; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ══════════════════════════════════════════════════════════════════════════════

class PrimeYardApp extends StatefulWidget {
  final AppSession session; final String? startupError;
  const PrimeYardApp({super.key,required this.session,this.startupError});
  @override State<PrimeYardApp> createState() => _PrimeYardAppState();
}
class _PrimeYardAppState extends State<PrimeYardApp> {
  late AppSession _s = widget.session;
  void _onIn(AppSession s) => setState(()=>_s=s);
  Future<void> _onOut() async { await AppSession.clear(); setState(()=>_s=const AppSession()); }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor:Pal.green,primary:Pal.green,secondary:Pal.gold,brightness:Brightness.light);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PrimeYard Workspace',
      theme: ThemeData(
        useMaterial3:true, colorScheme:scheme, scaffoldBackgroundColor:Pal.cream,
        textTheme: Theme.of(context).textTheme.apply(bodyColor:Pal.text,displayColor:Pal.text),
        appBarTheme: const AppBarTheme(backgroundColor:Colors.transparent,elevation:0,foregroundColor:Pal.text),
        cardTheme: CardThemeData(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20),side:const BorderSide(color:Pal.border))),
        inputDecorationTheme: InputDecorationTheme(filled:true,fillColor:Colors.white,contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Pal.border)),
          enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Pal.border)),
          focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Pal.green,width:1.5))),
        chipTheme: ChipThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(99))),
      ),
      home: _s.loggedIn
        ? Shell(session:_s,onOut:_onOut,onUpdate:_onIn)
        : LoginScreen(onIn:_onIn,startupErr:widget.startupError),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LOGIN
// ══════════════════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppSession> onIn; final String? startupErr;
  const LoginScreen({super.key,required this.onIn,this.startupErr});
  @override State<LoginScreen> createState() => _LoginState();
}
class _LoginState extends State<LoginScreen> {
  final _u=TextEditingController(), _p=TextEditingController();
  bool _loading=true; String? _err; BackendBootstrap? _boot;
  @override void initState() { super.initState(); _doBoot(); }
  Future<void> _doBoot() async {
    final b = await BackendService.bootstrap();
    if (!mounted) return;
    setState((){_boot=b;_loading=false;if(b.error!=null&&b.state.users.isEmpty)_err=b.error;});
  }
  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState((){_loading=true;_err=null;});
    final user = await BackendService.login(_u.text.trim(),_p.text);
    if (user==null) { setState((){_err='Incorrect username or password.';_loading=false;}); return; }
    final s = AppSession(loggedIn:true,id:(user['id']??'').toString(),username:(user['username']??'').toString(),displayName:(user['displayName']??user['username']??'User').toString(),role:(user['role']??'worker').toString());
    await s.persist();
    widget.onIn(s);
  }
  @override
  Widget build(BuildContext ctx) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient:LinearGradient(colors:[Pal.deep,Pal.green,Pal.soft],begin:Alignment.topLeft,end:Alignment.bottomRight)),
      child: SafeArea(child: Center(child: SingleChildScrollView(padding:const EdgeInsets.all(20),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:480),child:Card(child:Padding(padding:const EdgeInsets.fromLTRB(24,24,24,28),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Center(child:Image.asset('assets/logo-full.png',height:60)),
        const SizedBox(height:6),
        Text('Business Manager',textAlign:TextAlign.center,style:Theme.of(ctx).textTheme.titleMedium?.copyWith(color:Pal.muted,fontWeight:FontWeight.w600)),
        const SizedBox(height:6),
        Text('Your property, our pride.',textAlign:TextAlign.center,style:Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
        const SizedBox(height:14),
        Image.asset('assets/mascot.png',height:140,fit:BoxFit.contain),
        const SizedBox(height:14),
        if (_boot!=null) Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFF7F4EC),borderRadius:BorderRadius.circular(14),border:Border.all(color:Pal.border)),child:Row(children:[
          Icon(_boot!.hasRemoteData?Icons.cloud_done_rounded:Icons.cloud_off_rounded,color:_boot!.hasRemoteData?Pal.green:Pal.danger,size:16),
          const SizedBox(width:8),
          Expanded(child:Text(_boot!.hasRemoteData?'Live workspace connected':'Using cached data',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13))),
        ])),
        const SizedBox(height:14),
        TextField(controller:_u,textInputAction:TextInputAction.next,decoration:const InputDecoration(labelText:'Username',prefixIcon:Icon(Icons.person_outline_rounded))),
        const SizedBox(height:10),
        TextField(controller:_p,obscureText:true,onSubmitted:(_)=>_login(),decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline_rounded))),
        if (_err!=null) ...[const SizedBox(height:10),Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFFFEBEE),borderRadius:BorderRadius.circular(12)),child:Text(_err!,style:const TextStyle(color:Pal.danger,fontWeight:FontWeight.w700,fontSize:13)))],
        const SizedBox(height:16),
        FilledButton.icon(
          onPressed:_loading?null:_login,
          icon:_loading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.login_rounded),
          label:Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_loading?'Signing in…':'Sign in',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),
          style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16))),
        ),
      ])))))),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// WORKSPACE SHELL
// ══════════════════════════════════════════════════════════════════════════════

class Shell extends StatefulWidget {
  final AppSession session; final Future<void> Function() onOut; final ValueChanged<AppSession> onUpdate;
  const Shell({super.key,required this.session,required this.onOut,required this.onUpdate});
  @override State<Shell> createState() => _ShellState();
}
class _ShellState extends State<Shell> {
  int _idx=0;

  @override
  Widget build(BuildContext context) => StreamBuilder<WS>(
    stream: BackendService.streamState(),
    builder:(ctx,snap){
      if (snap.connectionState==ConnectionState.waiting&&!snap.hasData) return const Scaffold(body:Center(child:CircularProgressIndicator()));
      final st = snap.data??WS.empty();
      final pages = _pages(widget.session,st);
      if (_idx>=pages.length) _idx=0;
      final cur = pages[_idx];
      return Scaffold(
        appBar: AppBar(
          titleSpacing:16,
          title:Row(children:[
            Image.asset('assets/logo-mark.png',width:26,height:26),
            const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(cur.label,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
              Text(widget.session.displayName,style:const TextStyle(fontSize:11,color:Pal.muted)),
            ])),
          ]),
          actions:[IconButton(onPressed:()=>_profile(ctx,st),icon:CircleAvatar(backgroundColor:Pal.green,radius:15,child:Text(_ini(widget.session.displayName),style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w800))))],
        ),
        body: AnimatedSwitcher(duration:const Duration(milliseconds:180),child:cur.builder(ctx,st)),
        bottomNavigationBar: NavigationBar(height:68,selectedIndex:_idx,destinations:[for(final p in pages) NavigationDestination(icon:Icon(p.icon),label:p.short)],onDestinationSelected:(v)=>setState(()=>_idx=v)),
      );
    },
  );

  void _profile(BuildContext ctx, WS st) => showModalBottomSheet(context:ctx,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(_)=>SafeArea(child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[CircleAvatar(backgroundColor:Pal.green,radius:22,child:Text(_ini(widget.session.displayName),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))),const SizedBox(width:12),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(widget.session.displayName,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),Text('@${widget.session.username} · ${widget.session.role}',style:const TextStyle(color:Pal.muted,fontSize:12))])]),
    const SizedBox(height:16),
    _tile(ctx,Icons.lock_outline_rounded,'Change password',null,()=>{Navigator.pop(ctx),_changePw(ctx,st)}),
    _tile(ctx,Icons.logout_rounded,'Sign out',Pal.danger,()=>{Navigator.pop(ctx),widget.onOut()}),
  ]))));

  ListTile _tile(BuildContext ctx,IconData ico,String title,Color? col,VoidCallback fn)=>ListTile(leading:Icon(ico,color:col),title:Text(title,style:TextStyle(color:col)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),onTap:fn);

  void _changePw(BuildContext ctx, WS st) {
    final o=TextEditingController(),n=TextEditingController(),c2=TextEditingController();
    String? err;
    showDialog(context:ctx,builder:(dctx)=>StatefulBuilder(builder:(dctx,ss)=>AlertDialog(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),title:const Text('Change password',style:TextStyle(fontWeight:FontWeight.w900)),content:Column(mainAxisSize:MainAxisSize.min,children:[
      _pwf(o,'Current password'),const SizedBox(height:8),_pwf(n,'New password'),const SizedBox(height:8),_pwf(c2,'Confirm new password'),
      if(err!=null)...[const SizedBox(height:8),Text(err!,style:const TextStyle(color:Pal.danger,fontWeight:FontWeight.w700))],
    ]),actions:[
      TextButton(onPressed:()=>Navigator.pop(dctx),child:const Text('Cancel')),
      FilledButton(onPressed:() async {
        if(o.text.isEmpty||n.text.isEmpty||c2.text.isEmpty){ss(()=>err='All fields required.');return;}
        if(n.text!=c2.text){ss(()=>err='Passwords do not match.');return;}
        if(n.text.length<6){ss(()=>err='Min 6 characters.');return;}
        final cu=st.users.whereType<Map>().firstWhere((u)=>(u['username']??'').toString().toLowerCase()==widget.session.username.toLowerCase(),orElse:()=>{});
        if(cu.isEmpty){ss(()=>err='User not found.');return;}
        if(_hash(o.text)!=(cu['passwordHash']??'')){ss(()=>err='Current password incorrect.');return;}
        final up=st.users.whereType<Map>().map((u){final r=Map<String,dynamic>.from(u);if((r['username']??'').toString().toLowerCase()==widget.session.username.toLowerCase())r['passwordHash']=_hash(n.text);return r;}).toList();
        await BackendService.saveState(st.copyWith(users:up),by:widget.session.username);
        if(dctx.mounted)Navigator.pop(dctx);
        if(ctx.mounted)_snack(ctx,'Password changed!');
      },child:const Text('Change')),
    ])));
  }

  TextField _pwf(TextEditingController c, String l) => TextField(controller:c,obscureText:true,decoration:InputDecoration(labelText:l));

  List<_PD> _pages(AppSession s, WS st) {
    if (s.isWorker) return [
      _PD('My Route','Route',Icons.route_rounded,(c,st)=>WorkerRoutePage(s:s,st:st)),
      _PD('Clock','Clock',Icons.access_time_rounded,(c,st)=>ClockPage(s:s,st:st)),
      _PD('Equipment','Equip',Icons.handyman_rounded,(c,st)=>EquipmentPage(st:st,s:s)),
    ];
    if (s.isSupervisor) return [
      _PD('Dashboard','Home',Icons.dashboard_rounded,(c,st)=>DashboardPage(st:st)),
      _PD('Schedule','Jobs',Icons.calendar_month_rounded,(c,st)=>SchedulerPage(st:st,s:s)),
      _PD('Equipment','Equip',Icons.handyman_rounded,(c,st)=>EquipmentPage(st:st,s:s)),
      _PD('Jobs Log','Log',Icons.task_alt_rounded,(c,st)=>JobsLogPage(st:st)),
      _PD('Clock','Clock',Icons.punch_clock_rounded,(c,st)=>ClockEntriesPage(st:st)),
    ];
    return [
      _PD('Dashboard','Home',Icons.dashboard_rounded,(c,st)=>DashboardPage(st:st)),
      _PD('Clients','Clients',Icons.people_alt_rounded,(c,st)=>ClientsPage(st:st,s:s)),
      _PD('Invoices','Bills',Icons.receipt_long_rounded,(c,st)=>InvoicesPage(st:st,s:s)),
      _PD('Schedule','Jobs',Icons.calendar_month_rounded,(c,st)=>SchedulerPage(st:st,s:s)),
      _PD('Staff','Staff',Icons.badge_rounded,(c,st)=>EmployeesPage(st:st,s:s)),
      _PD('More','More',Icons.tune_rounded,(c,st)=>MorePage(st:st,s:s)),
    ];
  }
}

class _PD {
  final String label,short; final IconData icon; final Widget Function(BuildContext,WS) builder;
  _PD(this.label,this.short,this.icon,this.builder);
}

// ══════════════════════════════════════════════════════════════════════════════
// WORKER — MY ROUTE
// ══════════════════════════════════════════════════════════════════════════════

class WorkerRoutePage extends StatelessWidget {
  final AppSession s; final WS st;
  const WorkerRoutePage({super.key,required this.s,required this.st});
  @override
  Widget build(BuildContext ctx) {
    final jobs = st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((j){
      final w=(j['workerName']??'').toString().toLowerCase();
      return (w==s.displayName.toLowerCase()||w==s.username.toLowerCase()||w.isEmpty)&&(j['date']??'')==st.schedDate;
    }).toList();
    final done=jobs.where((j)=>j['done']==true).length;
    final inProg=jobs.where((j)=>j['status']=='in_progress').length;
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'My Route',sub:'${st.schedDate} · $done/${jobs.length} done${inProg>0?' · $inProg in progress':''}'),
      for (final j in jobs) _JobCard(job:j,onTap:()=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>JobDetailPage(job:j,s:s,st:st)))),
      if(jobs.isEmpty) const _Empty(icon:Icons.route_rounded,title:'No route today',sub:'No jobs assigned to you for today yet.'),
    ]);
  }
}

class _JobCard extends StatelessWidget {
  final Map<String,dynamic> job; final VoidCallback onTap;
  const _JobCard({required this.job,required this.onTap});
  @override
  Widget build(BuildContext ctx) {
    final done=job['done']==true;
    final inProg=job['status']=='in_progress';
    Color accent = done?Pal.green:inProg?Pal.gold:Pal.muted;
    IconData ico = done?Icons.check_circle_rounded:inProg?Icons.play_circle_rounded:Icons.radio_button_unchecked_rounded;
    return Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:InkWell(borderRadius:BorderRadius.circular(20),onTap:onTap,child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Icon(ico,color:accent,size:26),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text((job['name']??'Client').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
        if((job['address']??'').toString().isNotEmpty) Text(job['address'].toString(),style:const TextStyle(color:Pal.muted,fontSize:12)),
        if(inProg&&(job['startedAt']??'').toString().isNotEmpty) _LiveJobTimer(startedAt:job['startedAt'].toString()),
        if((job['notes']??'').toString().isNotEmpty) Text('📝 ${job['notes']}',style:const TextStyle(color:Pal.green,fontSize:11)),
      ])),
      if(done) Container(margin:const EdgeInsets.only(left:6),padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:Pal.green.withOpacity(.1),borderRadius:BorderRadius.circular(99)),child:const Text('Done',style:TextStyle(color:Pal.green,fontWeight:FontWeight.w800,fontSize:11))),
      const Icon(Icons.chevron_right_rounded,color:Pal.muted),
    ])))));
  }
}

// Live timer widget — shows elapsed time since startedAt, updates every second
class _LiveJobTimer extends StatefulWidget {
  final String startedAt;
  const _LiveJobTimer({required this.startedAt});
  @override State<_LiveJobTimer> createState() => _LiveJobTimerState();
}
class _LiveJobTimerState extends State<_LiveJobTimer> {
  Timer? _t; Duration _elapsed = Duration.zero;
  @override void initState() { super.initState(); _tick(); _t=Timer.periodic(const Duration(seconds:1),(_)=>_tick()); }
  @override void dispose() { _t?.cancel(); super.dispose(); }
  void _tick() { try { final start=DateTime.parse(widget.startedAt).toLocal(); if(mounted) setState(()=>_elapsed=DateTime.now().difference(start)); } catch(_){} }
  @override Widget build(BuildContext ctx) => Text('⏱ In progress: ${_fmt(_elapsed)}',style:const TextStyle(color:Pal.gold,fontWeight:FontWeight.w700,fontSize:11));
  String _fmt(Duration d) => '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
}

// ══════════════════════════════════════════════════════════════════════════════
// JOB DETAIL PAGE
// ══════════════════════════════════════════════════════════════════════════════

class JobDetailPage extends StatefulWidget {
  final Map<String,dynamic> job; final AppSession s; final WS st;
  const JobDetailPage({super.key,required this.job,required this.s,required this.st});
  @override State<JobDetailPage> createState() => _JobDetailState();
}
class _JobDetailState extends State<JobDetailPage> {
  late Map<String,dynamic> _j;
  final _notesCtrl=TextEditingController();
  bool _saving=false;
  final _picker=ImagePicker();
  String? _photoErr;

  @override void initState() { super.initState(); _j=Map<String,dynamic>.from(widget.job); _notesCtrl.text=(_j['notes']??'').toString(); }

  bool get _done => _j['done']==true;
  bool get _inProg => _j['status']=='in_progress';

  Future<void> _startJob() async {
    final now=DateTime.now();
    setState((){_j['status']='in_progress';_j['startedAt']=now.toIso8601String();_j['startedBy']=widget.s.username;});
    await _save();
  }

  Future<void> _markDone() async {
    final now=DateTime.now();
    setState((){_j['done']=true;_j['status']='done';_j['completedAt']=now.toIso8601String();_j['completedBy']=widget.s.username;});
    await _save();
  }

  Future<void> _markPending() async {
    setState((){_j['done']=false;_j['status']='pending';_j.remove('completedAt');_j.remove('completedBy');});
    await _save();
  }

  Future<void> _saveNotes() async {
    setState((){_j['notes']=_notesCtrl.text.trim();_saving=true;});
    await _save();
    setState(()=>_saving=false);
    if (mounted) _snack(context,'Notes saved');
  }

  Future<void> _pickPhoto(String type) async {
    setState(()=>_photoErr=null);
    try {
      final picked = await _picker.pickImage(source:ImageSource.camera,imageQuality:40,maxWidth:900,maxHeight:900);
      if (picked==null) return;
      setState(()=>_saving=true);
      final id = await BackendService.savePhoto(_j['id'].toString(),type,File(picked.path));
      if (id!=null) {
        final key = type=='before'?'beforePhotos':'afterPhotos';
        final list = List<String>.from(_j[key]??[]);
        list.add(id);
        setState((){_j[key]=list;});
        await _save();
        if (mounted) _snack(context,'${type=='before'?'Before':'After'} photo saved ✓');
      } else {
        setState(()=>_photoErr='Photo upload failed. Check your internet connection.');
      }
    } catch(e) { setState(()=>_photoErr='Camera error: $e'); }
    setState(()=>_saving=false);
  }

  Future<void> _save() async {
    final upd=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==_j['id'])return Map<String,dynamic>.from(_j);return r;}).toList();
    await BackendService.saveState(widget.st.copyWith(jobs:upd),by:widget.s.username);
  }

  @override
  Widget build(BuildContext ctx) {
    final before=List<String>.from(_j['beforePhotos']??[]);
    final after=List<String>.from(_j['afterPhotos']??[]);
    return Scaffold(
      appBar:AppBar(title:Text((_j['name']??'Job').toString(),style:const TextStyle(fontWeight:FontWeight.w900))),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
        // Status card
        Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Icon(_done?Icons.check_circle_rounded:_inProg?Icons.play_circle_rounded:Icons.circle_outlined,color:_done?Pal.green:_inProg?Pal.gold:Pal.muted,size:22),
            const SizedBox(width:8),
            Text(_done?'Completed':_inProg?'In Progress':'Pending',style:TextStyle(fontWeight:FontWeight.w800,color:_done?Pal.green:_inProg?Pal.gold:Pal.muted,fontSize:15)),
          ]),
          if((_j['address']??'').toString().isNotEmpty)...[const SizedBox(height:6),Row(children:[const Icon(Icons.location_on_rounded,color:Pal.muted,size:16),const SizedBox(width:4),Expanded(child:Text(_j['address'].toString(),style:const TextStyle(color:Pal.muted,fontSize:13)))])],
          if(_inProg&&(_j['startedAt']??'').isNotEmpty)...[const SizedBox(height:8),_LiveJobTimer(startedAt:_j['startedAt'].toString())],
          if(_done&&(_j['completedAt']??'').isNotEmpty)...[const SizedBox(height:6),Text('Completed ${_fmtDT(_j['completedAt'].toString())}',style:const TextStyle(color:Pal.green,fontSize:12))],
          const SizedBox(height:14),
          // Action buttons
          if(!_done&&!_inProg) FilledButton.icon(
            onPressed:_saving?null:_startJob,
            icon:const Icon(Icons.play_arrow_rounded),
            label:const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text('Start Job',style:TextStyle(fontSize:15,fontWeight:FontWeight.w700))),
            style:FilledButton.styleFrom(backgroundColor:Pal.gold,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
          ),
          if(_inProg) FilledButton.icon(
            onPressed:_saving?null:_markDone,
            icon:const Icon(Icons.check_rounded),
            label:const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text('Mark as Done',style:TextStyle(fontSize:15,fontWeight:FontWeight.w700))),
            style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
          ),
          if(_done)...[
            FilledButton.icon(onPressed:_saving?null:_markPending,icon:const Icon(Icons.undo_rounded),label:const Text('Mark as Pending'),style:FilledButton.styleFrom(backgroundColor:Pal.muted,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)))),
          ],
          if(!_done&&!_inProg)...[const SizedBox(height:8),
            OutlinedButton.icon(onPressed:_saving?null:_markDone,icon:const Icon(Icons.check_rounded),label:const Text('Skip to Done'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)))),
          ],
        ]))),
        const SizedBox(height:10),

        // Notes
        Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Text('Job Notes',style:TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
          const SizedBox(height:10),
          TextField(controller:_notesCtrl,maxLines:3,decoration:const InputDecoration(hintText:'Add site notes, instructions, observations…')),
          const SizedBox(height:10),
          OutlinedButton.icon(onPressed:_saving?null:_saveNotes,icon:_saving?const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_rounded,size:16),label:const Text('Save Notes'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)))),
        ]))),
        const SizedBox(height:10),
        if(_photoErr!=null) Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFFFEBEE),borderRadius:BorderRadius.circular(12)),child:Text(_photoErr!,style:const TextStyle(color:Pal.danger,fontWeight:FontWeight.w600,fontSize:13))),

        // Before photos
        _PhotoSection(title:'Before Photos',ids:before,onAdd:_saving?null:()=>_pickPhoto('before')),
        const SizedBox(height:10),
        _PhotoSection(title:'After Photos',ids:after,onAdd:_saving?null:()=>_pickPhoto('after')),
      ]),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  final String title; final List<String> ids; final VoidCallback? onAdd;
  const _PhotoSection({required this.title,required this.ids,this.onAdd});
  @override
  Widget build(BuildContext ctx) => Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
      if(onAdd!=null) FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.camera_alt_rounded,size:14),label:const Text('Take Photo'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),textStyle:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))),
    ]),
    if(ids.isNotEmpty)...[
      const SizedBox(height:12),
      SizedBox(height:110,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:ids.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i)=>_FSPhoto(id:ids[i]))),
    ] else ...[const SizedBox(height:8),const Text('No photos yet',style:TextStyle(color:Pal.muted,fontSize:13))],
  ])));
}

// Loads a photo from Firestore on demand
class _FSPhoto extends StatefulWidget {
  final String id; const _FSPhoto({required this.id});
  @override State<_FSPhoto> createState() => _FSPhotoState();
}
class _FSPhotoState extends State<_FSPhoto> {
  Uint8List? _b; bool _loading=true;
  @override void initState() { super.initState(); BackendService.loadPhoto(widget.id).then((b){if(mounted)setState((){_b=b;_loading=false;});}); }
  @override Widget build(BuildContext ctx) {
    if (_loading) return ClipRRect(borderRadius:BorderRadius.circular(10),child:Container(width:110,height:110,color:Pal.border,child:const Center(child:CircularProgressIndicator(strokeWidth:2))));
    if (_b==null) return ClipRRect(borderRadius:BorderRadius.circular(10),child:Container(width:110,height:110,color:Pal.border,child:const Icon(Icons.broken_image_rounded,color:Pal.muted)));
    return GestureDetector(
      onTap:()=>showDialog(context:ctx,builder:(_)=>Dialog(child:InteractiveViewer(child:Image.memory(_b!)))),
      child:ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.memory(_b!,width:110,height:110,fit:BoxFit.cover)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WORKER — CLOCK PAGE (with live elapsed timer)
// ══════════════════════════════════════════════════════════════════════════════

class ClockPage extends StatefulWidget {
  final AppSession s; final WS st;
  const ClockPage({super.key,required this.s,required this.st});
  @override State<ClockPage> createState() => _ClockPageState();
}
class _ClockPageState extends State<ClockPage> {
  bool _saving=false;
  Timer? _timer; Duration _elapsed=Duration.zero;
  @override void initState() { super.initState(); _startTick(); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }

  void _startTick() {
    _timer?.cancel();
    _timer=Timer.periodic(const Duration(seconds:1),(_){if(mounted){final ci=_lastIn;if(ci!=null){try{final t=DateTime.parse(ci['timestamp'].toString()).toLocal();setState(()=>_elapsed=DateTime.now().difference(t));}catch(_){}}else{setState(()=>_elapsed=Duration.zero);}}});
  }

  List<Map<String,dynamic>> get _mine => widget.st.clockEntries.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((e)=>(e['username']??'').toString().toLowerCase()==widget.s.username.toLowerCase()).toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
  Map<String,dynamic>? get _lastIn { final td=_mine.where((e)=>(e['date']??'')==_today()).toList(); return td.isNotEmpty&&td.first['type']=='in'?td.first:null; }
  bool get _clockedIn => _lastIn!=null;

  Future<void> _clock(String type) async {
    setState(()=>_saving=true);
    final now=DateTime.now();
    final entry={'id':now.millisecondsSinceEpoch.toString(),'userId':widget.s.id,'username':widget.s.username,'displayName':widget.s.displayName,'type':type,'timestamp':now.toIso8601String(),'date':_today()};
    await BackendService.saveState(widget.st.copyWith(clockEntries:[...widget.st.clockEntries,entry]),by:widget.s.username);
    setState(()=>_saving=false);
  }

  String _fmtEl(Duration d) => '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext ctx) {
    final today=_mine.where((e)=>(e['date']??'')==_today()).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'My Clock',sub:_today()),
      Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        // Status display
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:_clockedIn?const Color(0xFFE8F5E9):const Color(0xFFFFF8E1),borderRadius:BorderRadius.circular(18)),child:Column(children:[
          Icon(_clockedIn?Icons.login_rounded:Icons.logout_rounded,size:44,color:_clockedIn?Pal.green:Pal.gold),
          const SizedBox(height:8),
          Text(_clockedIn?'CLOCKED IN':'CLOCKED OUT',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17,color:_clockedIn?Pal.green:const Color(0xFFE65100))),
          const SizedBox(height:4),
          Text(DateFormat('HH:mm · EEEE d MMM').format(DateTime.now()),style:const TextStyle(color:Pal.muted,fontSize:13)),
          if(_clockedIn&&_elapsed.inSeconds>0)...[
            const SizedBox(height:10),
            Container(padding:const EdgeInsets.symmetric(horizontal:18,vertical:8),decoration:BoxDecoration(color:Pal.green.withOpacity(.1),borderRadius:BorderRadius.circular(99)),child:Text(_fmtEl(_elapsed),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:26,color:Pal.green,fontFeatures:[]))),
            const Text('Time clocked in',style:TextStyle(color:Pal.muted,fontSize:12)),
          ],
        ])),
        const SizedBox(height:18),
        FilledButton.icon(
          onPressed:_saving?null:()=>_clock(_clockedIn?'out':'in'),
          icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Icon(_clockedIn?Icons.logout_rounded:Icons.login_rounded),
          label:Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Text(_clockedIn?'Clock Out':'Clock In',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800))),
          style:FilledButton.styleFrom(backgroundColor:_clockedIn?Pal.danger:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
        ),
      ]))),
      const SizedBox(height:14),
      _SH(title:"Today's Activity",sub:'${today.length} entries'),
      for(final e in today) Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(
        leading:CircleAvatar(backgroundColor:e['type']=='in'?const Color(0xFFE8F5E9):const Color(0xFFFFEBEE),child:Icon(e['type']=='in'?Icons.login_rounded:Icons.logout_rounded,color:e['type']=='in'?Pal.green:Pal.danger,size:16)),
        title:Text(e['type']=='in'?'Clocked In':'Clocked Out',style:const TextStyle(fontWeight:FontWeight.w800)),
        trailing:Text(_fmtDT(e['timestamp']??''),style:const TextStyle(color:Pal.muted,fontSize:12)),
      ))),
      if(today.isEmpty) const _Empty(icon:Icons.access_time_rounded,title:'No entries today',sub:'Tap the button above to clock in.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EQUIPMENT PAGE (with explicit submit button)
// ══════════════════════════════════════════════════════════════════════════════

class EquipmentPage extends StatelessWidget {
  final WS st; final AppSession s;
  const EquipmentPage({super.key,required this.st,required this.s});

  Future<void> _seed() async {
    if (st.equipment.isNotEmpty) return;
    const seed=[{'id':'eq1','name':'Brush cutter','status':'ok'},{'id':'eq2','name':'Lawn mower','status':'ok'},{'id':'eq3','name':'Blower','status':'ok'},{'id':'eq4','name':'Hedge trimmer','status':'ok'},{'id':'eq5','name':'Compactor','status':'ok'}];
    await BackendService.saveState(st.copyWith(equipment:seed),by:s.username);
  }

  void _submitCheck(BuildContext ctx, Map<String,dynamic> item) {
    String selStatus=(item['status']??'ok').toString();
    final notesCtrl=TextEditingController();
    showDialog(context:ctx,builder:(dctx)=>StatefulBuilder(builder:(dctx,ss)=>AlertDialog(
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),
      title:Text('Check: ${item['name']}',style:const TextStyle(fontWeight:FontWeight.w900)),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Select condition:',style:TextStyle(fontWeight:FontWeight.w600,color:Pal.muted)),
        const SizedBox(height:12),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          for(final st in ['ok','issue','missing']) Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:ChoiceChip(
            label:Text(st.toUpperCase(),style:TextStyle(fontWeight:FontWeight.w800,color:selStatus==st?Colors.white:Pal.text)),
            selected:selStatus==st,
            selectedColor:st=='ok'?Pal.green:st=='issue'?Pal.gold:Pal.danger,
            onSelected:(_)=>ss(()=>selStatus=st),
          )),
        ]),
        const SizedBox(height:14),
        TextField(controller:notesCtrl,maxLines:2,decoration:const InputDecoration(labelText:'Notes (optional)',hintText:'Describe any issues…')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dctx),child:const Text('Cancel')),
        FilledButton.icon(
          onPressed:() async {
            Navigator.pop(dctx);
            final updEq=this.st.equipment.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==item['id'])r['status']=selStatus;return r;}).toList();
            final now=DateTime.now();
            final log={'id':now.millisecondsSinceEpoch.toString(),'equipmentId':item['id'],'equipmentName':item['name'],'status':selStatus,'notes':notesCtrl.text.trim(),'submittedBy':s.username,'submittedByName':s.displayName,'date':_today(),'timestamp':now.toIso8601String()};
            await BackendService.saveState(this.st.copyWith(equipment:updEq,checkLogs:[...this.st.checkLogs,log]),by:s.username);
            if(ctx.mounted) _snack(ctx,'Check submitted for ${item['name']}');
          },
          icon:const Icon(Icons.check_rounded),
          label:const Text('Submit Check'),
          style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
        ),
      ],
    )));
  }

  @override
  Widget build(BuildContext ctx) {
    final items=st.equipment.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(items.isEmpty) _seed();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Equipment Checks',sub:'${items.length} tracked items · ${_today()}'),
      Container(margin:const EdgeInsets.only(bottom:14),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Pal.infoBg,borderRadius:BorderRadius.circular(14)),child:const Row(children:[Icon(Icons.info_outline_rounded,color:Pal.infoFg,size:16),SizedBox(width:8),Expanded(child:Text('Tap an item, select its condition, and press Submit Check to log.',style:TextStyle(color:Pal.infoFg,fontSize:12)))])),
      for(final item in items) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.handyman_rounded,color:Pal.green),const SizedBox(width:10),Expanded(child:Text((item['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15))),_Pill(text:(item['status']??'ok').toString())]),
        const SizedBox(height:10),
        if((item['notes']??'').toString().isNotEmpty) Padding(padding:const EdgeInsets.only(bottom:8),child:Text(item['notes'].toString(),style:const TextStyle(color:Pal.muted,fontSize:12))),
        SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>_submitCheck(ctx,item),icon:const Icon(Icons.fact_check_outlined,size:16),label:const Text('Submit Check'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),side:const BorderSide(color:Pal.green),foregroundColor:Pal.green))),
      ])))),
      if(items.isEmpty) const _Empty(icon:Icons.handyman_rounded,title:'No equipment yet',sub:'Seeding default equipment…'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatelessWidget {
  final WS st; const DashboardPage({super.key,required this.st});
  @override
  Widget build(BuildContext ctx) {
    final active=st.clients.whereType<Map>().where((e)=>(e['active']??true)==true).length;
    final rec=st.clients.whereType<Map>().fold<double>(0,(s,e)=>s+_n(e['rate']));
    final out=st.invoices.whereType<Map>().where((e)=>(e['status']??'')=='unpaid').fold<double>(0,(s,e)=>s+_n(e['amount']));
    final tj=st.jobs.whereType<Map>().where((e)=>(e['date']??'')==st.schedDate).toList();
    final done=tj.where((e)=>(e['done']??false)==true).length;
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _Hero(st:st),const SizedBox(height:14),
      GridView.count(physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.15,shrinkWrap:true,children:[
        _Stat(title:'Active Clients',val:'$active',sub:'Recurring accounts',ico:Icons.people_alt_rounded,col:Pal.green),
        _Stat(title:'Monthly Revenue',val:_m(rec),sub:'Expected recurring',ico:Icons.payments_rounded,col:const Color(0xFF1565C0)),
        _Stat(title:'Outstanding',val:_m(out),sub:'Unpaid invoices',ico:Icons.receipt_long_rounded,col:Pal.danger),
        _Stat(title:'Jobs Today',val:'$done/${tj.length}',sub:'Completed',ico:Icons.task_alt_rounded,col:const Color(0xFF6A1B9A)),
      ]),
      const SizedBox(height:14),
      _SC(title:'Mission',child:const Text('Deliver dependable lawn and property care with professional standards, honest communication, and visible pride in every finished result.',style:TextStyle(height:1.6))),
      const SizedBox(height:12),
      _SC(title:'Core Values',child:Wrap(spacing:8,runSpacing:8,children:[for(final v in ['Reliability','Professional presentation','Respect for property','Clear communication','Consistent quality']) _Ch(v)])),
    ]);
  }
}

class _Hero extends StatelessWidget {
  final WS st; const _Hero({required this.st});
  @override
  Widget build(BuildContext ctx)=>Container(
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Pal.deep,Pal.green],begin:Alignment.topLeft,end:Alignment.bottomRight),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.15),blurRadius:16,offset:const Offset(0,8))]),
    padding:const EdgeInsets.all(20),
    child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('PrimeYard Workspace',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w900)),
        const SizedBox(height:6),
        const Text('Run jobs, invoices, staff and equipment from one app.',style:TextStyle(color:Color(0xE6FFFFFF),height:1.5,fontSize:13)),
        const SizedBox(height:12),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:Colors.white.withOpacity(.15),borderRadius:BorderRadius.circular(99)),child:Text(st.updatedAt==null?'Waiting for sync…':'Synced ${DateFormat('HH:mm').format(st.updatedAt!)}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:12))),
      ])),
      const SizedBox(width:8),
      Image.asset('assets/mascot.png',height:100),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CLIENTS (with sqm field + auto-pricing hint)
// ══════════════════════════════════════════════════════════════════════════════

class ClientsPage extends StatelessWidget {
  final WS st; final AppSession s;
  const ClientsPage({super.key,required this.st,required this.s});

  Future<void> _edit(BuildContext ctx, [Map<String,dynamic>? ex]) async {
    final nm=TextEditingController(text:ex?['name']?.toString()??'');
    final addr=TextEditingController(text:ex?['address']?.toString()??'');
    final rate=TextEditingController(text:ex!=null?_n(ex['rate']).toStringAsFixed(0):'');
    final sqm=TextEditingController(text:ex!=null?_n(ex['sqm']).toStringAsFixed(0):'');
    final act=ValueNotifier<bool>((ex?['active']??true)==true);
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:act,builder:(_,av,__)=>_Dlg(title:ex==null?'New Client':'Edit Client',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(nm,'Client name *'),const SizedBox(height:8),_tf(addr,'Property address'),const SizedBox(height:8),
      Row(children:[Expanded(child:_tf(sqm,'Property size (m²)',num:true)),const SizedBox(width:8),Expanded(child:_tf(rate,'Monthly rate (R)',num:true))]),
      const SizedBox(height:8),
      Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Pal.infoBg,borderRadius:BorderRadius.circular(10)),child:Text('💡 Leave rate blank to calculate from size using your pricing rules.',style:TextStyle(color:Pal.infoFg,fontSize:11))),
      const SizedBox(height:8),
      SwitchListTile(value:av,onChanged:(v)=>act.value=v,title:const Text('Active'),contentPadding:EdgeInsets.zero,dense:true),
    ]))));
    if(ok!=true||nm.text.trim().isEmpty) return;
    double calcRate = double.tryParse(rate.text.trim())??0;
    if(calcRate==0&&(sqm.text.trim().isNotEmpty)){
      final sqmVal=double.tryParse(sqm.text.trim())??0;
      final mowRate=_n(st.pricingRules['mowing']?['rate']);
      calcRate=sqmVal*mowRate;
    }
    final items=List<dynamic>.from(st.clients);
    if(ex==null) {
      items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':nm.text.trim(),'address':addr.text.trim(),'sqm':double.tryParse(sqm.text.trim())??0,'rate':calcRate,'active':act.value,'createdAt':_today()});
    } else {
      final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);
      if(i>=0) items[i]={...ex,'name':nm.text.trim(),'address':addr.text.trim(),'sqm':double.tryParse(sqm.text.trim())??0,'rate':calcRate,'active':act.value};
    }
    await BackendService.saveState(st.copyWith(clients:items),by:s.username);
  }

  Future<void> _del(BuildContext ctx, Map<String,dynamic> c) async {
    final ok=await _confirm(ctx,'Delete "${c['name']}"?');
    if(ok!=true) return;
    await BackendService.saveState(st.copyWith(clients:st.clients.where((e)=>e is Map&&e['id']!=c['id']).toList()),by:s.username);
  }

  @override
  Widget build(BuildContext ctx) {
    final clients=st.clients.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Clients',sub:'${clients.length} total',action:FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.add_rounded,size:16),label:const Text('Add'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:14,vertical:8)))),
      for(final c in clients) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(
        contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),
        leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(c['name']))),
        title:Text((c['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((c['address']??'No address').toString(),style:const TextStyle(fontSize:12)),
          Row(children:[
            Text(_m(_n(c['rate']))+'/mo',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:Pal.green)),
            if(_n(c['sqm'])>0)...[const Text(' · ',style:TextStyle(color:Pal.muted,fontSize:12)),Text('${_n(c['sqm']).toStringAsFixed(0)} m²',style:const TextStyle(fontSize:12,color:Pal.muted))],
          ]),
        ]),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          _Pill(text:(c['active']??true)?'Active':'Paused'),
          PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(ctx,c);else _del(ctx,c);},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'delete',child:Text('Delete',style:TextStyle(color:Pal.danger)))]),
        ]),
      ))),
      if(clients.isEmpty) const _Empty(icon:Icons.people_alt_rounded,title:'No clients yet',sub:'Add your first client.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INVOICES (with PDF generation + share)
// ══════════════════════════════════════════════════════════════════════════════

class InvoicesPage extends StatelessWidget {
  final WS st; final AppSession s;
  const InvoicesPage({super.key,required this.st,required this.s});

  Future<void> _edit(BuildContext ctx, [Map<String,dynamic>? ex]) async {
    final cl=TextEditingController(text:ex?['client']?.toString()??'');
    final am=TextEditingController(text:ex!=null?_n(ex['amount']).toStringAsFixed(2):'');
    final notes=TextEditingController(text:ex?['notes']?.toString()??'');
    final st2=ValueNotifier<String>((ex?['status']??'unpaid').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:st2,builder:(_,sv,__)=>_Dlg(title:ex==null?'New Invoice':'Edit Invoice',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(cl,'Client name *'),const SizedBox(height:8),_tf(am,'Amount (R) *',num:true),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:sv,items:const[DropdownMenuItem(value:'unpaid',child:Text('Unpaid')),DropdownMenuItem(value:'paid',child:Text('Paid'))],onChanged:(v)=>st2.value=v??'unpaid',decoration:const InputDecoration(labelText:'Status')),
      const SizedBox(height:8),TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notes / description')),
    ]))));
    if(ok!=true||cl.text.trim().isEmpty) return;
    final items=List<dynamic>.from(st.invoices);
    if(ex==null){
      items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'client':cl.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':st2.value,'notes':notes.text.trim(),'createdAt':_today(),'invoiceNo':'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'});
    } else {
      final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']);
      if(i>=0) items[i]={...ex,'client':cl.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':st2.value,'notes':notes.text.trim()};
    }
    await BackendService.saveState(st.copyWith(invoices:items),by:s.username);
  }

  Future<void> _toggle(Map<String,dynamic> inv) async {
    final upd=st.invoices.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==inv['id'])r['status']=r['status']=='paid'?'unpaid':'paid';return r;}).toList();
    await BackendService.saveState(st.copyWith(invoices:upd),by:s.username);
  }

  Future<void> _del(BuildContext ctx, Map<String,dynamic> inv) async {
    if(await _confirm(ctx,'Delete invoice for "${inv['client']}"?')!=true) return;
    await BackendService.saveState(st.copyWith(invoices:st.invoices.where((e)=>e is Map&&e['id']!=inv['id']).toList()),by:s.username);
  }

  Future<void> _pdf(BuildContext ctx, Map<String,dynamic> inv) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(pw.Context pctx){
      return pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
          pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
            pw.Text('PRIMEYARD',style:pw.TextStyle(fontSize:28,fontWeight:pw.FontWeight.bold,color:PdfColor.fromHex('1A6B30'))),
            pw.Text('Lawn & Property Maintenance',style:pw.TextStyle(fontSize:12,color:PdfColor.fromHex('6D665D'))),
            pw.Text('Your property, our pride.',style:pw.TextStyle(fontSize:10,color:PdfColor.fromHex('6D665D'))),
          ]),
          pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[
            pw.Text('INVOICE',style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),
            pw.Text((inv['invoiceNo']??'INV-${(inv['id']??'').toString().substring(0,8)}').toString(),style:pw.TextStyle(fontSize:12,color:PdfColor.fromHex('6D665D'))),
            pw.Text('Date: ${inv['createdAt']??_today()}',style:pw.TextStyle(fontSize:11)),
          ]),
        ]),
        pw.SizedBox(height:20),
        pw.Divider(color:PdfColor.fromHex('E6DED0')),
        pw.SizedBox(height:16),
        pw.Text('BILL TO',style:pw.TextStyle(fontSize:10,color:PdfColor.fromHex('6D665D'),fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:4),
        pw.Text((inv['client']??'Client').toString(),style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),
        pw.SizedBox(height:30),
        pw.Table(border:pw.TableBorder.all(color:PdfColor.fromHex('E6DED0'),width:.5),children:[
          pw.TableRow(decoration:pw.BoxDecoration(color:PdfColor.fromHex('E8F3EA')),children:[
            pw.Padding(padding:const pw.EdgeInsets.all(10),child:pw.Text('Description',style:pw.TextStyle(fontWeight:pw.FontWeight.bold))),
            pw.Padding(padding:const pw.EdgeInsets.all(10),child:pw.Text('Amount',style:pw.TextStyle(fontWeight:pw.FontWeight.bold))),
          ]),
          pw.TableRow(children:[
            pw.Padding(padding:const pw.EdgeInsets.all(10),child:pw.Text((inv['notes']?.toString().isNotEmpty==true?inv['notes'].toString():'Lawn & property maintenance services').toString())),
            pw.Padding(padding:const pw.EdgeInsets.all(10),child:pw.Text(_m(_n(inv['amount'])))),
          ]),
        ]),
        pw.SizedBox(height:10),
        pw.Align(alignment:pw.Alignment.centerRight,child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[
          pw.Divider(color:PdfColor.fromHex('1A6B30'),thickness:2),
          pw.Row(mainAxisAlignment:pw.MainAxisAlignment.end,children:[
            pw.Text('TOTAL DUE: ',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:14)),
            pw.Text(_m(_n(inv['amount'])),style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:18,color:PdfColor.fromHex('1A6B30'))),
          ]),
          pw.Text('Status: ${(inv['status']??'unpaid').toString().toUpperCase()}',style:pw.TextStyle(fontSize:12,color:inv['status']=='paid'?PdfColor.fromHex('1A6B30'):PdfColor.fromHex('C62828'),fontWeight:pw.FontWeight.bold)),
        ])),
        pw.Spacer(),
        pw.Divider(color:PdfColor.fromHex('E6DED0')),
        pw.SizedBox(height:8),
        pw.Text('Thank you for choosing PrimeYard! Payment is due within 30 days.',style:pw.TextStyle(fontSize:10,color:PdfColor.fromHex('6D665D'),fontStyle:pw.FontStyle.italic)),
      ]);
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes:bytes,filename:'PrimeYard_Invoice_${(inv['client']??'Client').toString().replaceAll(' ','_')}_${inv['createdAt']??_today()}.pdf');
  }

  @override
  Widget build(BuildContext ctx) {
    final invs=st.invoices.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    final out=invs.where((e)=>e['status']=='unpaid').fold<double>(0,(s,e)=>s+_n(e['amount']));
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Invoices',sub:'${invs.length} records · ${_m(out)} outstanding',action:FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.add_rounded,size:16),label:const Text('Add'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:14,vertical:8)))),
      for(final inv in invs) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.fromLTRB(14,12,6,12),child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((inv['client']??'Client').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
          Text('Created ${inv['createdAt']??'-'}  ·  ${inv['invoiceNo']??''}',style:const TextStyle(color:Pal.muted,fontSize:11)),
          if((inv['notes']??'').toString().isNotEmpty) Text(inv['notes'].toString(),style:const TextStyle(fontSize:12,color:Pal.muted)),
          const SizedBox(height:4),
          Row(children:[Text(_m(_n(inv['amount'])),style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:Pal.green)),const SizedBox(width:8),_Pill(text:(inv['status']??'unpaid').toString())]),
        ])),
        Column(mainAxisSize:MainAxisSize.min,children:[
          IconButton(icon:const Icon(Icons.picture_as_pdf_rounded,color:Pal.danger),tooltip:'Download/Share PDF',onPressed:()=>_pdf(ctx,inv)),
          PopupMenuButton<String>(
            onSelected:(v){if(v=='toggle')_toggle(inv);else if(v=='edit')_edit(ctx,inv);else _del(ctx,inv);},
            itemBuilder:(_)=>[
              PopupMenuItem(value:'toggle',child:Text(inv['status']=='paid'?'Mark as unpaid':'Mark as paid')),
              const PopupMenuItem(value:'edit',child:Text('Edit')),
              const PopupMenuItem(value:'delete',child:Text('Delete',style:TextStyle(color:Pal.danger))),
            ],
          ),
        ]),
      ])))),
      if(invs.isEmpty) const _Empty(icon:Icons.receipt_long_rounded,title:'No invoices yet',sub:'Add your first invoice.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCHEDULER
// ══════════════════════════════════════════════════════════════════════════════

class SchedulerPage extends StatefulWidget {
  final WS st; final AppSession s;
  const SchedulerPage({super.key,required this.st,required this.s});
  @override State<SchedulerPage> createState() => _SchedulerState();
}
class _SchedulerState extends State<SchedulerPage> {
  late DateTime _date;
  @override void initState() { super.initState(); _date=DateTime.tryParse(widget.st.schedDate)??DateTime.now(); }
  String get _ds => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _addJob(BuildContext ctx) async {
    final cl=TextEditingController(); final addr=TextEditingController(); final wk=TextEditingController();
    final workers=widget.st.emps.whereType<Map>().map((e)=>(e['name']??'').toString()).where((e)=>e.isNotEmpty).toList();
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:'Schedule Job',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(cl,'Client name *'),const SizedBox(height:8),_tf(addr,'Address'),const SizedBox(height:8),
      if(workers.isNotEmpty) DropdownButtonFormField<String>(value:null,items:[const DropdownMenuItem(value:'',child:Text('— Select worker —')),...workers.map((w)=>DropdownMenuItem(value:w,child:Text(w)))],onChanged:(v)=>wk.text=v??'',decoration:const InputDecoration(labelText:'Assign worker'))
      else _tf(wk,'Worker name'),
    ])));
    if(ok!=true||cl.text.trim().isEmpty) return;
    final jobs=List<dynamic>.from(widget.st.jobs);
    jobs.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':cl.text.trim(),'address':addr.text.trim(),'workerName':wk.text.trim(),'date':_ds,'done':false,'status':'pending','notes':'','beforePhotos':[],'afterPhotos':[]});
    await BackendService.saveState(widget.st.copyWith(jobs:jobs),by:widget.s.username);
  }

  Future<void> _editJob(BuildContext ctx, Map<String,dynamic> j) async {
    final cl=TextEditingController(text:(j['name']??'').toString()); final addr=TextEditingController(text:(j['address']??'').toString()); final wk=TextEditingController(text:(j['workerName']??'').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:'Edit Job',child:Column(mainAxisSize:MainAxisSize.min,children:[_tf(cl,'Client name *'),const SizedBox(height:8),_tf(addr,'Address'),const SizedBox(height:8),_tf(wk,'Worker name')])));
    if(ok!=true||cl.text.trim().isEmpty) return;
    final upd=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==j['id']){r['name']=cl.text.trim();r['address']=addr.text.trim();r['workerName']=wk.text.trim();}return r;}).toList();
    await BackendService.saveState(widget.st.copyWith(jobs:upd),by:widget.s.username);
  }

  Future<void> _delJob(BuildContext ctx, Map<String,dynamic> j) async {
    if(await _confirm(ctx,'Delete job for "${j['name']}"?')!=true) return;
    await BackendService.saveState(widget.st.copyWith(jobs:widget.st.jobs.where((e)=>e is Map&&e['id']!=j['id']).toList()),by:widget.s.username);
  }

  @override
  Widget build(BuildContext ctx) {
    final jobs=widget.st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((j)=>(j['date']??'')==_ds).toList();
    final done=jobs.where((j)=>j['done']==true).length;
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      // Date nav
      Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),child:Row(children:[
        IconButton(icon:const Icon(Icons.chevron_left_rounded),onPressed:()=>setState(()=>_date=_date.subtract(const Duration(days:1)))),
        Expanded(child:InkWell(onTap:()async{final p=await showDatePicker(context:ctx,initialDate:_date,firstDate:DateTime(2020),lastDate:DateTime(2030));if(p!=null)setState(()=>_date=p);},borderRadius:BorderRadius.circular(10),child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(children:[Text(DateFormat('EEEE').format(_date),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),Text(DateFormat('d MMMM yyyy').format(_date),style:const TextStyle(color:Pal.muted,fontSize:11))])))),
        IconButton(icon:const Icon(Icons.chevron_right_rounded),onPressed:()=>setState(()=>_date=_date.add(const Duration(days:1)))),
        TextButton(onPressed:()=>setState(()=>_date=DateTime.now()),child:const Text('Today')),
      ]))),
      const SizedBox(height:10),
      _SH(title:'Jobs',sub:'$done/${jobs.length} done',action:FilledButton.icon(onPressed:()=>_addJob(ctx),icon:const Icon(Icons.add_rounded,size:16),label:const Text('Add'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:14,vertical:8)))),
      for(final j in jobs) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.all(4),child:CheckboxListTile(
        controlAffinity:ListTileControlAffinity.leading,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
        value:j['done']==true,
        title:Text((j['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if((j['address']??'').toString().isNotEmpty) Text(j['address'].toString(),style:const TextStyle(fontSize:12)),
          Text((j['workerName']??'Unassigned').toString(),style:const TextStyle(color:Pal.muted,fontSize:11)),
          if(j['status']=='in_progress') Text('⏱ In progress since ${_fmtDT((j['startedAt']??'').toString())}',style:const TextStyle(color:Pal.gold,fontSize:11,fontWeight:FontWeight.w700)),
          if((j['notes']??'').toString().isNotEmpty) Text('📝 ${j['notes']}',style:const TextStyle(color:Pal.green,fontSize:11)),
        ]),
        secondary:PopupMenuButton<String>(
          onSelected:(v){if(v=='edit')_editJob(ctx,j);else _delJob(ctx,j);},
          itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'delete',child:Text('Delete',style:TextStyle(color:Pal.danger)))],
        ),
        onChanged:(_) async {
          final nd=!(j['done']==true);
          final upd=widget.st.jobs.whereType<Map>().map((e){final r=Map<String,dynamic>.from(e);if(r['id']==j['id']){r['done']=nd;r['status']=nd?'done':'pending';}return r;}).toList();
          await BackendService.saveState(widget.st.copyWith(jobs:upd),by:widget.s.username);
        },
      )))),
      if(jobs.isEmpty) const _Empty(icon:Icons.calendar_month_rounded,title:'No jobs scheduled',sub:'Add jobs to build the route for this day.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPLOYEES
// ══════════════════════════════════════════════════════════════════════════════

class EmployeesPage extends StatelessWidget {
  final WS st; final AppSession s;
  const EmployeesPage({super.key,required this.st,required this.s});

  Future<void> _edit(BuildContext ctx, [Map<String,dynamic>? ex]) async {
    final nm=TextEditingController(text:ex?['name']?.toString()??'');
    final rt=TextEditingController(text:ex!=null?_n(ex['dailyRate']).toStringAsFixed(0):'');
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>_Dlg(title:ex==null?'New Employee':'Edit Employee',child:Column(mainAxisSize:MainAxisSize.min,children:[_tf(nm,'Full name *'),const SizedBox(height:8),_tf(rt,'Daily rate (R)',num:true)])));
    if(ok!=true||nm.text.trim().isEmpty) return;
    final items=List<dynamic>.from(st.emps);
    if(ex==null) items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'name':nm.text.trim(),'dailyRate':double.tryParse(rt.text.trim())??0,'startDate':_today()});
    else { final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']); if(i>=0) items[i]={...ex,'name':nm.text.trim(),'dailyRate':double.tryParse(rt.text.trim())??0}; }
    await BackendService.saveState(st.copyWith(emps:items),by:s.username);
  }

  void _payroll(BuildContext ctx, Map<String,dynamic> emp) {
    final en=emp['name'].toString().toLowerCase();
    final entries=st.clockEntries.whereType<Map>().where((e)=>((e['displayName']??e['username']??'').toString().toLowerCase()).contains(en.split(' ').first)).toList();
    final days=entries.where((e)=>e['type']=='in').length;
    final total=days*_n(emp['dailyRate']);
    showModalBottomSheet(context:ctx,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(22))),builder:(_)=>Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(emp['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20)),
      Text('${_m(_n(emp['dailyRate']))} / day · Started ${emp['startDate']??'-'}',style:const TextStyle(color:Pal.muted)),
      const Divider(height:24),
      Row(children:[
        Expanded(child:_PBox(label:'Days Worked',val:'$days')),
        const SizedBox(width:10),
        Expanded(child:_PBox(label:'Total Wages',val:_m(total))),
      ]),
      const SizedBox(height:14),
      const Text('Based on clock-in records matched to this employee.',style:TextStyle(color:Pal.muted,fontSize:11),textAlign:TextAlign.center),
    ])));
  }

  @override
  Widget build(BuildContext ctx) {
    final emps=st.emps.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Employees',sub:'${emps.length} on record',action:FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.add_rounded,size:16),label:const Text('Add'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:14,vertical:8)))),
      for(final e in emps) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(
        contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),
        leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(e['name']))),
        title:Text((e['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('${_m(_n(e['dailyRate']))}/day · Since ${e['startDate']??'-'}'),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          IconButton(icon:const Icon(Icons.payments_rounded,color:Pal.green),tooltip:'Payroll',onPressed:()=>_payroll(ctx,e)),
          PopupMenuButton<String>(
            onSelected:(v) async {
              if(v=='edit') _edit(ctx,e);
              else if(await _confirm(ctx,'Remove "${e['name']}"?')==true) await BackendService.saveState(st.copyWith(emps:st.emps.where((x)=>x is Map&&x['id']!=e['id']).toList()),by:s.username);
            },
            itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Remove',style:TextStyle(color:Pal.danger)))],
          ),
        ]),
      ))),
      if(emps.isEmpty) const _Empty(icon:Icons.badge_rounded,title:'No employees yet',sub:'Add team members to track payroll.'),
    ]);
  }
}

class _PBox extends StatelessWidget {
  final String label,val; const _PBox({required this.label,required this.val});
  @override Widget build(BuildContext ctx)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(14)),child:Column(children:[Text(val,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20,color:Pal.green)),const SizedBox(height:4),Text(label,style:const TextStyle(color:Pal.muted,fontSize:11))]));
}

// ══════════════════════════════════════════════════════════════════════════════
// MORE PAGE
// ══════════════════════════════════════════════════════════════════════════════

class MorePage extends StatelessWidget {
  final WS st; final AppSession s;
  const MorePage({super.key,required this.st,required this.s});
  void _go(BuildContext ctx,Widget w) => Navigator.push(ctx,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(),body:w)));
  @override
  Widget build(BuildContext ctx)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
    _SH(title:'More Tools',sub:'Extra workspace controls'),
    _AT(ico:Icons.calculate_rounded,title:'Quotes & Estimates',sub:'Create quotes with automatic pricing calculator',tap:()=>_go(ctx,QuotesPage(st:st,s:s))),
    _AT(ico:Icons.handyman_rounded,title:'Equipment',sub:'Equipment checks and status log',tap:()=>_go(ctx,EquipmentPage(st:st,s:s))),
    _AT(ico:Icons.task_alt_rounded,title:'Jobs Log',sub:'All jobs with date filters and status',tap:()=>_go(ctx,JobsLogPage(st:st))),
    _AT(ico:Icons.punch_clock_rounded,title:'Clock Entries',sub:'All staff clock-in/out records',tap:()=>_go(ctx,ClockEntriesPage(st:st))),
    _AT(ico:Icons.checklist_rounded,title:'Equipment Logs',sub:'Submitted equipment check history',tap:()=>_go(ctx,CheckLogsPage(st:st))),
    _AT(ico:Icons.price_change_rounded,title:'Pricing Rules',sub:'Edit service rates used in quote calculator',tap:()=>_go(ctx,PricingRulesPage(st:st,s:s))),
    if(s.isMaster) _AT(ico:Icons.manage_accounts_rounded,title:'User Management',sub:'Add, edit, and remove staff accounts',tap:()=>_go(ctx,UserManagementPage(st:st,s:s))),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// QUOTES PAGE + CALCULATOR
// ══════════════════════════════════════════════════════════════════════════════

class QuotesPage extends StatelessWidget {
  final WS st; final AppSession s;
  const QuotesPage({super.key,required this.st,required this.s});

  void _calculator(BuildContext ctx) => showModalBottomSheet(context:ctx,isScrollControlled:true,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(_)=>QuoteCalculatorSheet(st:st,onSave:(q) async { final items=List<dynamic>.from(st.quotes); items.insert(0,q); await BackendService.saveState(st.copyWith(quotes:items),by:s.username); }));

  Future<void> _edit(BuildContext ctx, [Map<String,dynamic>? ex]) async {
    final cl=TextEditingController(text:ex?['client']?.toString()??'');
    final addr=TextEditingController(text:ex?['address']?.toString()??'');
    final desc=TextEditingController(text:ex?['description']?.toString()??'');
    final am=TextEditingController(text:ex!=null?_n(ex['amount']).toStringAsFixed(0):'');
    final st2=ValueNotifier<String>((ex?['status']??'pending').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:st2,builder:(_,sv,__)=>_Dlg(title:ex==null?'New Quote':'Edit Quote',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(cl,'Client name *'),const SizedBox(height:8),_tf(addr,'Property address'),const SizedBox(height:8),
      TextField(controller:desc,maxLines:2,decoration:const InputDecoration(labelText:'Work description')),const SizedBox(height:8),
      _tf(am,'Amount (R)',num:true),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:sv,items:const[DropdownMenuItem(value:'pending',child:Text('Pending')),DropdownMenuItem(value:'accepted',child:Text('Accepted')),DropdownMenuItem(value:'declined',child:Text('Declined'))],onChanged:(v)=>st2.value=v??'pending',decoration:const InputDecoration(labelText:'Status')),
    ]))));
    if(ok!=true||cl.text.trim().isEmpty) return;
    final items=List<dynamic>.from(st.quotes);
    if(ex==null) items.insert(0,{'id':DateTime.now().millisecondsSinceEpoch.toString(),'client':cl.text.trim(),'address':addr.text.trim(),'description':desc.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':st2.value,'createdAt':_today(),'createdBy':s.username});
    else { final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']); if(i>=0) items[i]={...ex,'client':cl.text.trim(),'address':addr.text.trim(),'description':desc.text.trim(),'amount':double.tryParse(am.text.trim())??0,'status':st2.value}; }
    await BackendService.saveState(st.copyWith(quotes:items),by:s.username);
  }

  Color _sc(String s){switch(s){case'accepted':return Pal.green;case'declined':return Pal.danger;default:return Pal.gold;}}

  @override
  Widget build(BuildContext ctx)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
    _SH(title:'Quotes',sub:'${st.quotes.length} total',action:Row(mainAxisSize:MainAxisSize.min,children:[
      OutlinedButton.icon(onPressed:()=>_calculator(ctx),icon:const Icon(Icons.calculate_rounded,size:14),label:const Text('Calculator'),style:OutlinedButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),foregroundColor:Pal.green,side:const BorderSide(color:Pal.green),padding:const EdgeInsets.symmetric(horizontal:10,vertical:8))),
      const SizedBox(width:6),
      FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.add_rounded,size:14),label:const Text('Add'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:10,vertical:8))),
    ])),
    for(final q in st.quotes.whereType<Map>().map((e)=>Map<String,dynamic>.from(e))) Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Expanded(child:Text((q['client']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15))),
        Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:_sc((q['status']??'pending').toString()).withOpacity(.12),borderRadius:BorderRadius.circular(99)),child:Text((q['status']??'pending').toString().toUpperCase(),style:TextStyle(color:_sc((q['status']??'pending').toString()),fontWeight:FontWeight.w800,fontSize:11))),
        PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(ctx,q);else if(v=='del')BackendService.saveState(st.copyWith(quotes:st.quotes.where((e)=>e is Map&&e['id']!=q['id']).toList()),by:s.username);},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:Pal.danger)))]),
      ]),
      if((q['address']??'').toString().isNotEmpty) Text(q['address'].toString(),style:const TextStyle(color:Pal.muted,fontSize:12)),
      if((q['description']??'').toString().isNotEmpty) Text(q['description'].toString(),style:const TextStyle(fontSize:12)),
      const SizedBox(height:6),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text(_m(_n(q['amount'])),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:Pal.green)),
        Text('${q['createdAt']??'-'}',style:const TextStyle(color:Pal.muted,fontSize:11)),
      ]),
      if(q['breakdown'] is List&&(q['breakdown'] as List).isNotEmpty)...[
        const SizedBox(height:6),
        const Divider(),
        const Text('Breakdown:',style:TextStyle(fontWeight:FontWeight.w700,fontSize:11,color:Pal.muted)),
        for(final b in (q['breakdown'] as List).whereType<Map>()) Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text((b['label']??'').toString(),style:const TextStyle(fontSize:11)),Text(_m(_n(b['amount'])),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700))]),
      ],
    ])))),
    if(st.quotes.isEmpty) const _Empty(icon:Icons.calculate_rounded,title:'No quotes yet',sub:'Use the Calculator to create auto-priced quotes.'),
  ]);
}

// Quote Calculator Sheet
class QuoteCalculatorSheet extends StatefulWidget {
  final WS st; final Function(Map<String,dynamic>) onSave;
  const QuoteCalculatorSheet({super.key,required this.st,required this.onSave});
  @override State<QuoteCalculatorSheet> createState() => _QCalcState();
}
class _QCalcState extends State<QuoteCalculatorSheet> {
  final _cl=TextEditingController(); final _addr=TextEditingController(); final _desc=TextEditingController();
  final _sqm=TextEditingController(); final _hrs=TextEditingController(text:'1');
  Map<String,bool> _sel={};
  double _override=0; bool _useOverride=false;

  @override void initState() { super.initState(); for(final k in widget.st.pricingRules.keys) _sel[k]=false; }

  double get _sqmVal => double.tryParse(_sqm.text)??0;
  double get _hrsVal => double.tryParse(_hrs.text)??1;

  List<Map<String,dynamic>> get _breakdown {
    final list=<Map<String,dynamic>>[];
    for(final entry in widget.st.pricingRules.entries) {
      if(_sel[entry.key]!=true) continue;
      final r=Map<String,dynamic>.from(entry.value as Map);
      final unit=(r['unit']??'sqm').toString();
      final rate=_n(r['rate']);
      final qty = unit=='sqm'?_sqmVal:unit=='hour'?_hrsVal:1.0;
      final amt=qty*rate;
      list.add({'key':entry.key,'label':r['label']??entry.key,'rate':rate,'unit':unit,'qty':qty,'amount':amt});
    }
    return list;
  }

  double get _total => _useOverride?_override:_breakdown.fold(0,(s,e)=>s+_n(e['amount']));

  @override
  Widget build(BuildContext ctx)=>Padding(
    padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom,left:16,right:16,top:16),
    child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Quote Calculator',style:TextStyle(fontWeight:FontWeight.w900,fontSize:20)),
      const SizedBox(height:4),
      const Text('Select services, enter size — price calculates automatically.',style:TextStyle(color:Pal.muted,fontSize:12)),
      const SizedBox(height:14),
      _tf(_cl,'Client name *'),const SizedBox(height:8),_tf(_addr,'Property address'),const SizedBox(height:8),
      TextField(controller:_desc,maxLines:2,decoration:const InputDecoration(labelText:'Work description')),
      const SizedBox(height:14),
      const Text('Property size & hours',style:TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
      const SizedBox(height:6),
      Row(children:[Expanded(child:_tf(_sqm,'Size (m²)',num:true,onChanged:()=>setState((){}),)),const SizedBox(width:8),Expanded(child:_tf(_hrs,'Hours needed',num:true,onChanged:()=>setState((){})))]),
      const SizedBox(height:14),
      const Text('Services required',style:TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
      const SizedBox(height:6),
      Wrap(spacing:8,runSpacing:6,children:[
        for(final entry in widget.st.pricingRules.entries)
          FilterChip(
            label:Text((Map<String,dynamic>.from(entry.value as Map)['label']??entry.key).toString()),
            selected:_sel[entry.key]==true,
            onSelected:(v){setState((){_sel[entry.key]=v;});},
            selectedColor:Pal.green.withOpacity(.15),
            checkmarkColor:Pal.green,
          ),
      ]),
      if(_breakdown.isNotEmpty)...[
        const SizedBox(height:14),
        Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Text('Price Breakdown',style:TextStyle(fontWeight:FontWeight.w800,fontSize:13,color:Pal.green)),
          const SizedBox(height:8),
          for(final b in _breakdown) Padding(padding:const EdgeInsets.only(bottom:4),child:Row(children:[
            Expanded(child:Text('${b['label']} (${b['unit']=='sqm'?'${b['qty'].toStringAsFixed(0)}m²':b['unit']=='hour'?'${b['qty'].toStringAsFixed(1)}h':'1×'})',style:const TextStyle(fontSize:12))),
            Text(_m(_n(b['amount'])),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
          ])),
          const Divider(),
          Row(children:[const Expanded(child:Text('TOTAL',style:TextStyle(fontWeight:FontWeight.w900))),Text(_m(_total),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:Pal.green))]),
        ])),
        const SizedBox(height:8),
        Row(children:[
          Checkbox(value:_useOverride,onChanged:(v)=>setState(()=>_useOverride=v??false)),
          const Text('Override price: '),
          Expanded(child:TextField(decoration:const InputDecoration(prefixText:'R ',isDense:true,contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:8)),keyboardType:TextInputType.number,onChanged:(v){_override=double.tryParse(v)??0;setState((){});},enabled:_useOverride)),
        ]),
      ],
      const SizedBox(height:14),
      FilledButton.icon(
        onPressed:_cl.text.trim().isEmpty||_breakdown.isEmpty?null:()async{
          final q={'id':DateTime.now().millisecondsSinceEpoch.toString(),'client':_cl.text.trim(),'address':_addr.text.trim(),'description':_desc.text.trim().isNotEmpty?_desc.text.trim():'Lawn & property maintenance: ${_breakdown.map((b)=>b['label']).join(', ')}','amount':_total,'status':'pending','createdAt':_today(),'sqm':_sqmVal,'breakdown':_breakdown};
          await widget.onSave(q);
          if(ctx.mounted)Navigator.pop(ctx);
        },
        icon:const Icon(Icons.check_rounded),
        label:Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_breakdown.isEmpty?'Select at least one service':'Save Quote — ${_m(_total)}',style:const TextStyle(fontSize:15,fontWeight:FontWeight.w700))),
        style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
      ),
      const SizedBox(height:20),
    ])),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PRICING RULES PAGE
// ══════════════════════════════════════════════════════════════════════════════

class PricingRulesPage extends StatelessWidget {
  final WS st; final AppSession s;
  const PricingRulesPage({super.key,required this.st,required this.s});

  Future<void> _edit(BuildContext ctx, String key, Map<String,dynamic> rule) async {
    final lbl=TextEditingController(text:rule['label']?.toString()??'');
    final rate=TextEditingController(text:_n(rule['rate']).toStringAsFixed(2));
    final unit=ValueNotifier<String>((rule['unit']??'sqm').toString());
    final ok=await showDialog<bool>(context:ctx,builder:(_)=>ValueListenableBuilder(valueListenable:unit,builder:(_,u,__)=>_Dlg(title:'Edit Rate: ${rule['label']}',child:Column(mainAxisSize:MainAxisSize.min,children:[
      _tf(lbl,'Service name'),const SizedBox(height:8),_tf(rate,'Rate (R)',num:true),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:u,items:const[DropdownMenuItem(value:'sqm',child:Text('Per m²')),DropdownMenuItem(value:'hour',child:Text('Per hour')),DropdownMenuItem(value:'visit',child:Text('Per visit'))],onChanged:(v)=>unit.value=v??'sqm',decoration:const InputDecoration(labelText:'Unit')),
    ]))));
    if(ok!=true) return;
    final newRules=Map<String,dynamic>.from(st.pricingRules);
    newRules[key]={'label':lbl.text.trim(),'rate':double.tryParse(rate.text.trim())??_n(rule['rate']),'unit':unit.value};
    await BackendService.saveState(st.copyWith(pricingRules:newRules),by:s.username);
  }

  @override
  Widget build(BuildContext ctx)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
    _SH(title:'Pricing Rules',sub:'Rates used in quote calculator'),
    Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Pal.infoBg,borderRadius:BorderRadius.circular(12)),child:const Text('These rates are used to automatically calculate quote prices based on property size or hours.',style:TextStyle(color:Pal.infoFg,fontSize:12))),
    for(final entry in st.pricingRules.entries) _do(ctx,entry),
  ]);

  Widget _do(BuildContext ctx, MapEntry<String,dynamic> e) {
    final r=Map<String,dynamic>.from(e.value as Map);
    final unit=(r['unit']??'sqm').toString();
    return Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(
      title:Text((r['label']??e.key).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text('${_m(_n(r['rate']))} per ${unit=='sqm'?'m²':unit}'),
      trailing:IconButton(icon:const Icon(Icons.edit_rounded,color:Pal.green),onPressed:()=>_edit(ctx,e.key,r)),
    )));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// JOBS LOG (with date filter)
// ══════════════════════════════════════════════════════════════════════════════

class JobsLogPage extends StatefulWidget {
  final WS st; const JobsLogPage({super.key,required this.st});
  @override State<JobsLogPage> createState() => _JobsLogState();
}
class _JobsLogState extends State<JobsLogPage> {
  String _filter='all'; // all, today, done, pending, in_progress
  DateTime? _from, _to;

  List<Map<String,dynamic>> get _jobs {
    var jobs=widget.st.jobs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList()
      ..sort((a,b)=>(b['date']??'').toString().compareTo((a['date']??'').toString()));
    if(_filter=='done') jobs=jobs.where((j)=>j['done']==true).toList();
    else if(_filter=='pending') jobs=jobs.where((j)=>j['done']!=true&&j['status']!='in_progress').toList();
    else if(_filter=='in_progress') jobs=jobs.where((j)=>j['status']=='in_progress').toList();
    else if(_filter=='today') jobs=jobs.where((j)=>(j['date']??'')==_today()).toList();
    if(_from!=null) { final fs=DateFormat('yyyy-MM-dd').format(_from!); jobs=jobs.where((j)=>(j['date']??'')>=fs).toList(); }
    if(_to!=null) { final ts=DateFormat('yyyy-MM-dd').format(_to!); jobs=jobs.where((j)=>(j['date']??'')<=ts).toList(); }
    return jobs;
  }

  @override
  Widget build(BuildContext ctx) {
    final jobs=_jobs;
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Jobs Log',sub:'${jobs.length} matching'),
      // Filter chips
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        for(final f in [('all','All'),('today','Today'),('in_progress','In Progress'),('done','Done'),('pending','Pending')])
          Padding(padding:const EdgeInsets.only(right:8,bottom:8),child:FilterChip(label:Text(f.$2),selected:_filter==f.$1,onSelected:(_)=>setState(()=>_filter=f.$1),selectedColor:Pal.green.withOpacity(.15),checkmarkColor:Pal.green)),
      ])),
      // Date range
      Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(children:[
        const Icon(Icons.date_range_rounded,color:Pal.muted,size:16),const SizedBox(width:6),
        Expanded(child:InkWell(onTap:()async{final d=await showDatePicker(context:ctx,initialDate:_from??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2030));if(d!=null)setState(()=>_from=d);},child:Text(_from==null?'From date':DateFormat('d MMM yyyy').format(_from!),style:TextStyle(color:_from==null?Pal.muted:Pal.text,fontSize:13)))),
        const Text('→',style:TextStyle(color:Pal.muted)),
        Expanded(child:InkWell(onTap:()async{final d=await showDatePicker(context:ctx,initialDate:_to??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2030));if(d!=null)setState(()=>_to=d);},child:Text(_to==null?'To date':DateFormat('d MMM yyyy').format(_to!),style:TextStyle(color:_to==null?Pal.muted:Pal.text,fontSize:13)))),
        if(_from!=null||_to!=null) IconButton(icon:const Icon(Icons.clear_rounded,size:16,color:Pal.muted),onPressed:()=>setState((){_from=null;_to=null;})),
      ]))),
      const SizedBox(height:8),
      for(final j in jobs) Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(
        contentPadding:const EdgeInsets.all(14),
        leading:Icon(j['done']==true?Icons.check_circle_rounded:j['status']=='in_progress'?Icons.play_circle_rounded:Icons.radio_button_unchecked_rounded,color:j['done']==true?Pal.green:j['status']=='in_progress'?Pal.gold:Pal.muted,size:26),
        title:Text((j['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${j['date']??'-'} · ${j['address']??''}',style:const TextStyle(fontSize:12)),
          Text((j['workerName']??'Unassigned').toString(),style:const TextStyle(color:Pal.muted,fontSize:11)),
          if((j['notes']??'').toString().isNotEmpty) Text('📝 ${j['notes']}',style:const TextStyle(color:Pal.green,fontSize:11)),
          if(j['done']==true&&(j['completedAt']??'').isNotEmpty) Text('✓ Done at ${_fmtDT(j['completedAt'].toString())}',style:const TextStyle(color:Pal.green,fontSize:11)),
        ]),
      ))),
      if(jobs.isEmpty) const _Empty(icon:Icons.task_alt_rounded,title:'No jobs match',sub:'Try changing the filter or date range.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CLOCK ENTRIES (admin view)
// ══════════════════════════════════════════════════════════════════════════════

class ClockEntriesPage extends StatefulWidget {
  final WS st; const ClockEntriesPage({super.key,required this.st});
  @override State<ClockEntriesPage> createState() => _CEState();
}
class _CEState extends State<ClockEntriesPage> {
  String _who='';
  @override
  Widget build(BuildContext ctx) {
    final entries=widget.st.clockEntries.whereType<Map>().map((e)=>Map<String,dynamic>.from(e))
      .where((e)=>_who.isEmpty||(e['displayName']??e['username']??'').toString().toLowerCase().contains(_who.toLowerCase()))
      .toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Clock Entries',sub:'${entries.length} records'),
      TextField(decoration:const InputDecoration(hintText:'Search by name…',prefixIcon:Icon(Icons.search_rounded),isDense:true),onChanged:(v)=>setState(()=>_who=v)),
      const SizedBox(height:10),
      for(final e in entries) Padding(padding:const EdgeInsets.only(bottom:6),child:Card(child:ListTile(
        leading:CircleAvatar(backgroundColor:e['type']=='in'?const Color(0xFFE8F5E9):const Color(0xFFFFEBEE),child:Icon(e['type']=='in'?Icons.login_rounded:Icons.logout_rounded,color:e['type']=='in'?Pal.green:Pal.danger,size:16)),
        title:Text((e['displayName']??e['username']??'?').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('@${e['username']??''} · ${e['date']??''}'),
        trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(e['type']=='in'?'Clock In':'Clock Out',style:TextStyle(fontWeight:FontWeight.w700,color:e['type']=='in'?Pal.green:Pal.danger,fontSize:12)),Text(_fmtDT(e['timestamp']??''),style:const TextStyle(color:Pal.muted,fontSize:11))]),
      ))),
      if(entries.isEmpty) const _Empty(icon:Icons.punch_clock_rounded,title:'No entries',sub:'Clock entries appear here when staff clock in/out.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EQUIPMENT CHECK LOGS
// ══════════════════════════════════════════════════════════════════════════════

class CheckLogsPage extends StatelessWidget {
  final WS st; const CheckLogsPage({super.key,required this.st});
  @override
  Widget build(BuildContext ctx) {
    final logs=st.checkLogs.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList()..sort((a,b)=>(b['timestamp']??'').toString().compareTo((a['timestamp']??'').toString()));
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Equipment Logs',sub:'${logs.length} submissions'),
      for(final l in logs) Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(
        contentPadding:const EdgeInsets.all(14),
        leading:const Icon(Icons.handyman_rounded,color:Pal.green),
        title:Text((l['equipmentName']??'Equipment').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('By ${l['submittedByName']??l['submittedBy']??'?'} · ${l['date']??''}'),if((l['notes']??'').toString().isNotEmpty) Text(l['notes'].toString(),style:const TextStyle(color:Pal.muted,fontSize:12))]),
        trailing:_Pill(text:(l['status']??'ok').toString()),
      ))),
      if(logs.isEmpty) const _Empty(icon:Icons.checklist_rounded,title:'No check logs',sub:'Equipment checks will appear here when submitted.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// USER MANAGEMENT
// ══════════════════════════════════════════════════════════════════════════════

class UserManagementPage extends StatelessWidget {
  final WS st; final AppSession s;
  const UserManagementPage({super.key,required this.st,required this.s});

  Future<void> _edit(BuildContext ctx, [Map<String,dynamic>? ex]) async {
    final dn=TextEditingController(text:ex?['displayName']?.toString()??'');
    final un=TextEditingController(text:ex?['username']?.toString()??'');
    final pw=TextEditingController(); final pw2=TextEditingController();
    final role=ValueNotifier<String>((ex?['role']??'worker').toString());
    String? err;
    final ok=await showDialog<bool>(context:ctx,builder:(dctx)=>StatefulBuilder(builder:(dctx,ss)=>AlertDialog(
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),
      title:Text(ex==null?'Create User':'Edit User',style:const TextStyle(fontWeight:FontWeight.w900)),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        _tf(dn,'Display name *'),const SizedBox(height:8),
        TextField(controller:un,decoration:const InputDecoration(labelText:'Username *'),enabled:ex==null),const SizedBox(height:8),
        ValueListenableBuilder(valueListenable:role,builder:(_,rv,__)=>DropdownButtonFormField<String>(value:rv,items:const[DropdownMenuItem(value:'master_admin',child:Text('Master Admin')),DropdownMenuItem(value:'admin',child:Text('Admin')),DropdownMenuItem(value:'supervisor',child:Text('Supervisor')),DropdownMenuItem(value:'worker',child:Text('Worker'))],onChanged:(v)=>role.value=v??'worker',decoration:const InputDecoration(labelText:'Role'))),
        const SizedBox(height:8),
        TextField(controller:pw,obscureText:true,decoration:InputDecoration(labelText:ex==null?'Password *':'New password (blank = keep)')),const SizedBox(height:8),
        TextField(controller:pw2,obscureText:true,decoration:const InputDecoration(labelText:'Confirm password')),
        if(err!=null)...[const SizedBox(height:8),Text(err!,style:const TextStyle(color:Pal.danger,fontWeight:FontWeight.w700))],
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:(){
          if(dn.text.trim().isEmpty||un.text.trim().isEmpty){ss(()=>err='Name and username required.');return;}
          if(ex==null&&pw.text.isEmpty){ss(()=>err='Password required.');return;}
          if(pw.text.isNotEmpty&&pw.text!=pw2.text){ss(()=>err='Passwords do not match.');return;}
          if(pw.text.isNotEmpty&&pw.text.length<6){ss(()=>err='Min 6 characters.');return;}
          Navigator.pop(dctx,true);
        },child:Text(ex==null?'Create':'Save')),
      ],
    )));
    if(ok!=true) return;
    if(ex==null&&st.users.whereType<Map>().any((u)=>(u['username']??'').toString().toLowerCase()==un.text.trim().toLowerCase())) { if(ctx.mounted)_snack(ctx,'Username already taken'); return; }
    final hash=pw.text.isNotEmpty?_hash(pw.text):(ex?['passwordHash']??'').toString();
    final items=List<dynamic>.from(st.users);
    if(ex==null) items.add({'id':DateTime.now().millisecondsSinceEpoch.toString(),'username':un.text.trim(),'displayName':dn.text.trim(),'role':role.value,'passwordHash':hash,'createdAt':_today()});
    else { final i=items.indexWhere((e)=>e is Map&&e['id']==ex['id']); if(i>=0) items[i]={...ex,'displayName':dn.text.trim(),'role':role.value,'passwordHash':hash}; }
    await BackendService.saveState(st.copyWith(users:items),by:s.username);
    if(ctx.mounted) _snack(ctx,ex==null?'User created!':'User updated!');
  }

  Future<void> _del(BuildContext ctx, Map<String,dynamic> user) async {
    if((user['username']??'')==s.username){_snack(ctx,"Can't delete your own account");return;}
    if(await _confirm(ctx,'Delete account "${user['displayName']}"?')!=true) return;
    await BackendService.saveState(st.copyWith(users:st.users.where((e)=>e is Map&&e['id']!=user['id']).toList()),by:s.username);
  }

  @override
  Widget build(BuildContext ctx) {
    final users=st.users.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
      _SH(title:'Users',sub:'${users.length} accounts',action:FilledButton.icon(onPressed:()=>_edit(ctx),icon:const Icon(Icons.person_add_rounded,size:14),label:const Text('Add User'),style:FilledButton.styleFrom(backgroundColor:Pal.green,foregroundColor:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.symmetric(horizontal:12,vertical:8)))),
      for(final u in users) Padding(padding:const EdgeInsets.only(bottom:8),child:Card(child:ListTile(
        contentPadding:const EdgeInsets.fromLTRB(14,10,6,10),
        leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Text(_ini(u['displayName']))),
        title:Text((u['displayName']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('@${u['username']??''} · ${u['role']??'worker'}'),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          if((u['username']??'')==s.username) const _Pill(text:'You'),
          PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(ctx,u);else _del(ctx,u);},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'del',child:Text('Delete',style:TextStyle(color:Pal.danger)))]),
        ]),
      ))),
      if(users.isEmpty) const _Empty(icon:Icons.manage_accounts_rounded,title:'No users',sub:'Add the first user account.'),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _SH extends StatelessWidget {
  final String title,sub; final Widget? action;
  const _SH({required this.title,required this.sub,this.action});
  @override Widget build(BuildContext ctx)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),Text(sub,style:const TextStyle(color:Pal.muted,fontSize:12))])),if(action!=null) action!]));
}
class _SC extends StatelessWidget {
  final String title; final Widget child; const _SC({required this.title,required this.child});
  @override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900)),const SizedBox(height:8),child])));
}
class _Stat extends StatelessWidget {
  final String title,val,sub; final IconData ico; final Color col;
  const _Stat({required this.title,required this.val,required this.sub,required this.ico,required this.col});
  @override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(ico,color:col,size:22),const Spacer(),Text(title,style:const TextStyle(color:Pal.muted,fontWeight:FontWeight.w700,fontSize:11)),const SizedBox(height:4),Text(val,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),Text(sub,style:const TextStyle(fontSize:11,color:Pal.muted))])));
}
class _Ch extends StatelessWidget {
  final String t; const _Ch(this.t);
  @override Widget build(BuildContext ctx)=>Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),decoration:BoxDecoration(color:const Color(0xFFE8F3EA),borderRadius:BorderRadius.circular(99)),child:Text(t,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12)));
}
class _Pill extends StatelessWidget {
  final String text; const _Pill({required this.text});
  @override Widget build(BuildContext ctx){
    final l=text.toLowerCase(); Color bg,fg;
    switch(l){case'paid':case'ok':case'active':case'accepted':case'you':bg=const Color(0xFFE8F5E9);fg=Pal.green;break;case'issue':case'pending':bg=const Color(0xFFFFF8E1);fg=const Color(0xFFE65100);break;case'missing':case'unpaid':case'declined':bg=const Color(0xFFFFEBEE);fg=Pal.danger;break;default:bg=const Color(0xFFF1F1F1);fg=Pal.muted;}
    return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(99)),child:Text(text,style:TextStyle(color:fg,fontWeight:FontWeight.w800,fontSize:11)));
  }
}
class _AT extends StatelessWidget {
  final IconData ico; final String title,sub; final VoidCallback tap;
  const _AT({required this.ico,required this.title,required this.sub,required this.tap});
  @override Widget build(BuildContext ctx)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.all(14),leading:CircleAvatar(backgroundColor:const Color(0xFFE8F3EA),child:Icon(ico,color:Pal.green)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(sub,style:const TextStyle(fontSize:12)),trailing:const Icon(Icons.chevron_right_rounded),onTap:tap)));
}
class _Empty extends StatelessWidget {
  final IconData icon; final String title,sub;
  const _Empty({required this.icon,required this.title,required this.sub});
  @override Widget build(BuildContext ctx)=>Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(children:[Icon(icon,size:42,color:Pal.green),const SizedBox(height:12),Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),const SizedBox(height:6),Text(sub,textAlign:TextAlign.center,style:const TextStyle(color:Pal.muted))])));
}
class _Dlg extends StatelessWidget {
  final String title; final Widget child;
  const _Dlg({required this.title,required this.child});
  @override Widget build(BuildContext ctx)=>AlertDialog(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),content:SingleChildScrollView(child:child),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]);
}

// ══════════════════════════════════════════════════════════════════════════════
// UTILITIES
// ══════════════════════════════════════════════════════════════════════════════

TextField _tf(TextEditingController c, String l, {bool num=false, VoidCallback? onChanged}) =>
  TextField(controller:c,keyboardType:num?TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:l),onChanged:onChanged!=null?(_)=>onChanged():null);

Future<bool?> _confirm(BuildContext ctx, String msg) => showDialog<bool>(context:ctx,builder:(_)=>AlertDialog(title:const Text('Confirm'),content:Text(msg),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(style:FilledButton.styleFrom(backgroundColor:Pal.danger),onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));

void _snack(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(msg),behavior:SnackBarBehavior.floating,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))));

String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v')??0;
String _m(double v) => 'R${v.toStringAsFixed(2)}';
String _ini(dynamic n) { final p=(n??'').toString().trim().split(RegExp(r'\s+')).where((e)=>e.isNotEmpty).toList(); if(p.isEmpty)return'P'; return p.take(2).map((e)=>e[0].toUpperCase()).join(); }
String _fmtDT(String iso) { try { return DateFormat('HH:mm · d MMM yyyy').format(DateTime.parse(iso).toLocal()); } catch(_) { return iso; } }

dynamic _safe(dynamic v) {
  if(v is Timestamp) return v.toDate().toIso8601String();
  if(v is DateTime) return v.toIso8601String();
  if(v is Map) return v.map((k,val)=>MapEntry(k.toString(),_safe(val)));
  if(v is Iterable) return v.map(_safe).toList();
  return v;
}

Map<String,dynamic> _safeMap(Map<String,dynamic> d) => Map<String,dynamic>.from(_safe(d) as Map);

// ── Password hash (matches web app exactly) ────────────────────────────────
String _hash(String msg) {
  int n(int x) => x & 0xffffffff;
  const k = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  var h0=0x6a09e667,h1=0xbb67ae85,h2=0x3c6ef372,h3=0xa54ff53a,h4=0x510e527f,h5=0x9b05688c,h6=0x1f83d9ab,h7=0x5be0cd19;
  final bytes=<int>[];
  for(var i=0;i<msg.length;i++){final c=msg.codeUnitAt(i);if(c<128){bytes.add(c);}else if(c<2048){bytes.add((c>>6)|192);bytes.add((c&63)|128);}else{bytes.add((c>>12)|224);bytes.add(((c>>6)&63)|128);bytes.add((c&63)|128);}}
  final bl=bytes.length; final bits=bl*8;
  bytes.add(0x80);
  while(bytes.length%64!=56)bytes.add(0);
  bytes.addAll([0,0,0,0,bits~/ 0x100000000,(bits>>24)&0xff,(bits>>16)&0xff,(bits>>8)&0xff,bits&0xff]);
  while(bytes.length%64!=0)bytes.add(0);
  for(var i=0;i<bytes.length;i+=64){
    final w=List<int>.filled(64,0);
    for(var j=0;j<16;j++) w[j]=(bytes[i+j*4]<<24)|(bytes[i+j*4+1]<<16)|(bytes[i+j*4+2]<<8)|bytes[i+j*4+3];
    for(var j=16;j<64;j++){final s0=n(((w[j-15]>>7)|(w[j-15]<<25))^((w[j-15]>>18)|(w[j-15]<<14))^(w[j-15]>>3));final s1=n(((w[j-2]>>17)|(w[j-2]<<15))^((w[j-2]>>19)|(w[j-2]<<13))^(w[j-2]>>10));w[j]=n(w[j-16]+s0+w[j-7]+s1);}
    var a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,hh=h7;
    for(var j=0;j<64;j++){final s1=n(((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7)));final ch=(e&f)^((~e)&g);final t1=n(hh+s1+ch+k[j]+w[j]);final s0=n(((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10)));final maj=(a&b)^(a&c)^(b&d);final t2=n(s0+maj);hh=g;g=f;f=e;e=n(d+t1);d=c;c=b;b=a;a=n(t1+t2);}
    h0=n(h0+a);h1=n(h1+b);h2=n(h2+c);h3=n(h3+d);h4=n(h4+e);h5=n(h5+f);h6=n(h6+g);h7=n(h7+hh);
  }
  return [h0,h1,h2,h3,h4,h5,h6,h7].map((x)=>x.toRadixString(16).padLeft(8,'0')).join();
}
