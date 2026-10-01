import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:intl/intl.dart';

/**
 * AI COACH - Democratizing Personal Coaching
 * Features: Browse/Create/Share AI Coaches, Personal Context,
 * Real-time Chat with Gemini 3, RevenueCat IAP
 */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat
  await Purchases.configure(
    PurchasesConfiguration('goog_BVRlSXngWejnToyQMpLReoklWrH'),
  );

  runApp(const AICoachApp());
}

class AICoachApp extends StatelessWidget {
  const AICoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Coach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// === MODELS ===

enum UserTier { free, pro, premium }

class UserSession {
  final String userId;
  final String email;
  int trialsRemaining;
  int coachCreationCredits;
  int chatCredits;
  UserTier tier;
  String? contextText;
  String? valuesText;

  UserSession({
    required this.userId,
    required this.email,
    this.trialsRemaining = 5,
    this.coachCreationCredits = 0,
    this.chatCredits = 0,
    this.tier = UserTier.free,
    this.contextText,
    this.valuesText,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    userId: json['user_id'] ?? '',
    email: json['email'] ?? '',
    trialsRemaining: json['trials_remaining'] ?? 5,
    coachCreationCredits: json['coach_creation_credits'] ?? 0,
    chatCredits: json['chat_credits'] ?? 0,
    tier: UserTier.values.firstWhere(
      (t) => t.toString().split('.').last == (json['tier'] ?? 'free'),
      orElse: () => UserTier.free,
    ),
    contextText: json['context_text'],
    valuesText: json['values_text'],
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'trials_remaining': trialsRemaining,
    'coach_creation_credits': coachCreationCredits,
    'chat_credits': chatCredits,
    'tier': tier.toString().split('.').last,
    'context_text': contextText,
    'values_text': valuesText,
  };
}

class Coach {
  final String id;
  final String name;
  final String description;
  final String expertise;
  final String systemPrompt;
  final String creatorId;
  final bool isPublic;
  final int shareCount;
  final DateTime createdAt;

  Coach({
    required this.id,
    required this.name,
    required this.description,
    required this.expertise,
    required this.systemPrompt,
    required this.creatorId,
    required this.isPublic,
    this.shareCount = 0,
    required this.createdAt,
  });

  factory Coach.fromJson(Map<String, dynamic> json) => Coach(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    expertise: json['expertise'] ?? '',
    systemPrompt: json['system_prompt'] ?? '',
    creatorId: json['creator_id'] ?? '',
    isPublic: json['is_public'] ?? false,
    shareCount: json['share_count'] ?? 0,
    createdAt: DateTime.parse(json['created_at']),
  );
}

class Message {
  final String role;
  final String content;
  final DateTime timestamp;

  Message({required this.role, required this.content, required this.timestamp});

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    role: json['role'] ?? '',
    content: json['content'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };
}

// === API SERVICE ===

class ApiService {
  static const String baseUrl =
      'https://aico-dwd4bddyggaygrgg.eastus-01.azurewebsites.net';

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/profile'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateContext(
    String userId,
    String? contextText,
    String? valuesText,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/$userId/context'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'context_text': contextText,
        'values_text': valuesText,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<List<Coach>> getCoaches({bool publicOnly = true}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/coaches?public_only=$publicOnly'),
    );
    final List<dynamic> data = jsonDecode(response.body)['coaches'];
    return data.map((c) => Coach.fromJson(c)).toList();
  }

  static Future<Map<String, dynamic>> createCoach(
    String userId,
    String name,
    String description,
    String expertise,
    bool isPublic,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/coaches/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'description': description,
        'expertise': expertise,
        'is_public': isPublic,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> sendMessage(
    String userId,
    String coachId,
    String message,
    List<Message> history,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'coach_id': coachId,
        'message': message,
        'history': history.map((m) => m.toJson()).toList(),
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<void> shareCoach(String coachId) async {
    await http.post(
      Uri.parse('$baseUrl/coaches/$coachId/share'),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

// === AUTH WRAPPER ===

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  UserSession? session;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');

    if (userData != null) {
      setState(() {
        session = UserSession.fromJson(jsonDecode(userData));
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  void handleAuth(UserSession user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_session', jsonEncode(user.toJson()));
    setState(() => session = user);

    // === SYNC WITH REVENUECAT ===
    try {
      await Purchases.logIn(user.userId);
      await Purchases.setEmail(user.email);

      // UPDATE THIS STRING FOR EACH APP:
      await Purchases.setAttributes({
        'app_name':
            'AICoach', // Change to 'MumWise', 'AICoach', 'PacksLight', etc.
        'signup_tier': user.tier.toString(),
      });
    } catch (e) {
      debugPrint('RevenueCat user sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return session == null
        ? LoginScreen(onSuccess: handleAuth)
        : MainNavigation(
          user: session!,
          onSessionUpdate: (u) => setState(() => session = u),
        );
  }
}

// === LOGIN SCREEN ===

class LoginScreen extends StatefulWidget {
  final Function(UserSession) onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Password confirmation check for registration
    if (!isLogin && _passController.text != _confirmPassController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response =
          isLogin
              ? await ApiService.login(
                _emailController.text,
                _passController.text,
              )
              : await ApiService.register(
                _emailController.text,
                _passController.text,
              );

      if (response['success'] == true) {
        widget.onSuccess(UserSession.fromJson(response['user']));
      } else {
        _showError(response['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      _showError('Network error. Please check your connection.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.psychology_outlined,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'AI Coach',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const Text(
                      'Guidance at the right moment',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.contains('@') ? null : 'Invalid email',
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    TextFormField(
                      controller: _passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.length >= 6 ? null : 'Min 6 characters',
                    ),

                    // Confirm Password Field (only for registration)
                    if (!isLogin) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPassController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.black87),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator:
                            (v) => v!.length >= 6 ? null : 'Min 6 characters',
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF6366F1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child:
                            isLoading
                                ? const CircularProgressIndicator()
                                : Text(
                                  isLogin ? 'Sign In' : 'Create Account',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Toggle Login/Register
                    TextButton(
                      onPressed:
                          () => setState(() {
                            isLogin = !isLogin;
                            _confirmPassController.clear();
                          }),
                      child: Text(
                        isLogin
                            ? 'New here? Create an account'
                            : 'Already have an account? Sign in',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === MAIN NAVIGATION ===

class MainNavigation extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onSessionUpdate;

  const MainNavigation({
    super.key,
    required this.user,
    required this.onSessionUpdate,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _updatePages();
  }

  @override
  void didUpdateWidget(MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _updatePages();
    }
  }

  void _updatePages() {
    _pages = [
      DiscoverScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      MyCoachesScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      ContextScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      UpgradeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      ProfileScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        elevation: 0,
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'My Coaches',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Context',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Upgrade',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// === DISCOVER SCREEN ===

class DiscoverScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const DiscoverScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Coach> _coaches = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCoaches();
  }

  Future<void> _loadCoaches() async {
    setState(() => _isLoading = true);
    try {
      final coaches = await ApiService.getCoaches();
      setState(() {
        _coaches = coaches;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Coach> get filteredCoaches {
    if (_searchQuery.isEmpty) return _coaches;
    return _coaches
        .where(
          (c) =>
              c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              c.description.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              c.expertise.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Discover Coaches',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search coaches...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),

          // Coaches Grid
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredCoaches.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No coaches found',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                    : RefreshIndicator(
                      onRefresh: _loadCoaches,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.85,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: filteredCoaches.length,
                        itemBuilder: (context, index) {
                          final coach = filteredCoaches[index];
                          return _CoachCard(
                            coach: coach,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ChatScreen(
                                        user: widget.user,
                                        coach: coach,
                                        onUpdate: widget.onUpdate,
                                      ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  final Coach coach;
  final VoidCallback onTap;

  const _CoachCard({required this.coach, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Color(0xFF6366F1),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                coach.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                coach.expertise,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                coach.description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.share, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${coach.shareCount}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// === MY COACHES SCREEN ===

class MyCoachesScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const MyCoachesScreen({
    super.key,
    required this.user,
    required this.onUpdate,
  });

  @override
  State<MyCoachesScreen> createState() => _MyCoachesScreenState();
}

class _MyCoachesScreenState extends State<MyCoachesScreen> {
  List<Coach> _myCoaches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyCoaches();
  }

  Future<void> _loadMyCoaches() async {
    setState(() => _isLoading = true);
    try {
      final coaches = await ApiService.getCoaches(publicOnly: false);
      setState(() {
        _myCoaches =
            coaches.where((c) => c.creatorId == widget.user.userId).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _createCoach() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CreateCoachScreen(
              user: widget.user,
              onUpdate: widget.onUpdate,
              onCreated: _loadMyCoaches,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Coaches',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _createCoach,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Coach',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _myCoaches.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No coaches yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _createCoach,
                      icon: const Icon(Icons.add),
                      label: const Text('Create your first coach'),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _loadMyCoaches,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _myCoaches.length,
                  itemBuilder: (context, index) {
                    final coach = _myCoaches[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.psychology,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        title: Text(
                          coach.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          coach.expertise,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (coach.isPublic)
                              const Icon(Icons.public, size: 16),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ChatScreen(
                                    user: widget.user,
                                    coach: coach,
                                    onUpdate: widget.onUpdate,
                                  ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCoach,
        icon: const Icon(Icons.add),
        label: const Text('Create Coach'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
    );
  }
}

// === CREATE COACH SCREEN ===

class CreateCoachScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;
  final VoidCallback onCreated;

  const CreateCoachScreen({
    super.key,
    required this.user,
    required this.onUpdate,
    required this.onCreated,
  });

  @override
  State<CreateCoachScreen> createState() => _CreateCoachScreenState();
}

class _CreateCoachScreenState extends State<CreateCoachScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _expertiseController = TextEditingController();
  bool _isPublic = true;
  bool _isCreating = false;

  Future<void> _createCoach() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.user.coachCreationCredits <= 0 &&
        widget.user.trialsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isCreating = true);

    try {
      final response = await ApiService.createCoach(
        widget.user.userId,
        _nameController.text,
        _descriptionController.text,
        _expertiseController.text,
        _isPublic,
      );

      if (response['success'] == true) {
        // Update credits
        if (widget.user.coachCreationCredits > 0) {
          widget.user.coachCreationCredits--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showSuccess('Coach created successfully!');
        widget.onCreated();
        Navigator.pop(context);
      } else {
        _showError(response['message'] ?? 'Creation failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isCreating = false);
    }
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your coach creation credits. Upgrade to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create AI Coach'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 64,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(height: 16),
              const Text(
                'Design Your Coach',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Credits: ${widget.user.coachCreationCredits > 0 ? widget.user.coachCreationCredits : widget.user.trialsRemaining}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Coach Name',
                  hintText: 'e.g., Productivity Coach',
                ),
                validator: (v) => v!.isEmpty ? 'Please enter a name' : null,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _expertiseController,
                decoration: const InputDecoration(
                  labelText: 'Expertise',
                  hintText: 'e.g., Time Management, Goal Setting',
                ),
                validator: (v) => v!.isEmpty ? 'Please enter expertise' : null,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText:
                      'What does this coach help with? What\'s their approach?',
                  alignLabelWithHint: true,
                ),
                validator:
                    (v) => v!.isEmpty ? 'Please enter a description' : null,
              ),

              const SizedBox(height: 24),

              SwitchListTile(
                title: const Text('Make Public'),
                subtitle: const Text(
                  'Allow others to discover and use this coach',
                ),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 32),

              if (_isCreating)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _createCoach,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Create Coach',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Be specific about the coach\'s expertise\n'
                      '• Describe their coaching style and approach\n'
                      '• Consider what problems they solve',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _expertiseController.dispose();
    super.dispose();
  }
}

// === CHAT SCREEN ===

class ChatScreen extends StatefulWidget {
  final UserSession user;
  final Coach coach;
  final Function(UserSession) onUpdate;

  const ChatScreen({
    super.key,
    required this.user,
    required this.coach,
    required this.onUpdate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isSending = false;

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    if (widget.user.chatCredits <= 0 && widget.user.trialsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    final userMessage = Message(
      role: 'user',
      content: _messageController.text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final response = await ApiService.sendMessage(
        widget.user.userId,
        widget.coach.id,
        userMessage.content,
        _messages,
      );

      if (response['success'] == true) {
        final assistantMessage = Message(
          role: 'assistant',
          content: response['message'],
          timestamp: DateTime.now(),
        );

        setState(() {
          _messages.add(assistantMessage);
        });

        // Update credits
        if (widget.user.chatCredits > 0) {
          widget.user.chatCredits--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _scrollToBottom();
      } else {
        _showError(response['message'] ?? 'Failed to send message');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your chat credits. Upgrade to continue coaching!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _shareCoach() async {
    await ApiService.shareCoach(widget.coach.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coach shared! Link copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.coach.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.coach.expertise,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _shareCoach,
            icon: const Icon(Icons.share),
            tooltip: 'Share Coach',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child:
                _messages.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.psychology,
                              size: 40,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start a conversation',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              widget.coach.description,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isUser = message.role == 'user';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisAlignment:
                                isUser
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser) ...[
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF6366F1,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.psychology,
                                    size: 20,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        isUser
                                            ? const Color(0xFF6366F1)
                                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.content,
                                        style: TextStyle(
                                          color:
                                              isUser
                                                  ? Colors.white
                                                  : Colors.black87,
                                          fontSize: 15,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat(
                                          'HH:mm',
                                        ).format(message.timestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              isUser
                                                  ? Colors.white70
                                                  : Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),

          // Typing Indicator
          if (_isSending)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      size: 20,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thinking...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Ask for guidance...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// === CONTEXT SCREEN ===

class ContextScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const ContextScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
  final _contextController = TextEditingController();
  final _valuesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contextController.text = widget.user.contextText ?? '';
    _valuesController.text = widget.user.valuesText ?? '';
  }

  Future<void> _saveContext() async {
    setState(() => _isSaving = true);

    try {
      final response = await ApiService.updateContext(
        widget.user.userId,
        _contextController.text.isEmpty ? null : _contextController.text,
        _valuesController.text.isEmpty ? null : _valuesController.text,
      );

      if (response['success'] == true) {
        widget.user.contextText = _contextController.text;
        widget.user.valuesText = _valuesController.text;
        widget.onUpdate(widget.user);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Context saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save context'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Personal Context',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_pin_outlined,
              size: 64,
              color: Color(0xFF6366F1),
            ),
            const SizedBox(height: 16),
            const Text(
              'Help your coaches understand you',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The more context you provide, the better guidance you\'ll receive',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),

            const Text(
              'About You',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contextController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText:
                    'Who are you? What are you working on? What challenges are you facing?\n\nExample: I\'m a product manager at a startup. I struggle with prioritization and saying no...',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Your Values',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _valuesController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText:
                    'What matters most to you? What principles guide your decisions?\n\nExample: Integrity, continuous learning, work-life balance, creating value for others...',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 32),

            if (_isSaving)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _saveContext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Context',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Privacy',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your personal context is private and only used to personalize your coaching conversations. It\'s never shared with other users.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contextController.dispose();
    _valuesController.dispose();
    super.dispose();
  }
}

// === UPGRADE SCREEN ===

class UpgradeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const UpgradeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isProcessing = false;

  Future<void> _purchaseSubscription(String productId) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        final purchaserInfo = await Purchases.purchasePackage(package);

        if (purchaserInfo.customerInfo.entitlements.all[productId]?.isActive ??
            false) {
          if (productId.contains('pro')) {
            widget.user.tier = UserTier.pro;
            widget.user.coachCreationCredits = 11;
            widget.user.chatCredits = 50;
          } else if (productId.contains('premium')) {
            widget.user.tier = UserTier.premium;
            widget.user.coachCreationCredits = 20;
            widget.user.chatCredits = 100;
          }

          widget.onUpdate(widget.user);
          _showSuccess('Subscription activated!');
        }
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _purchaseCredits(String productId, int credits) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        await Purchases.purchasePackage(package);

        widget.user.trialsRemaining += credits;
        widget.onUpdate(widget.user);
        _showSuccess('$credits credits added!');
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body:
          _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 80,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unlock Your Potential',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Get unlimited access to AI coaching',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    // Current Tier
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stars, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Text(
                            'Current: ${widget.user.tier.toString().split('.').last.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'Monthly Plans',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Pro',
                      price: '\$25/month',
                      features: const [
                        '11 Coach Creations',
                        '50 Chat Sessions',
                        'Priority Support',
                        'Advanced Features',
                      ],
                      color: const Color(0xFF6366F1),
                      onTap: () => _purchaseSubscription('pro'),
                    ),

                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Premium',
                      price: '\$35/month',
                      features: const [
                        '20 Coach Creations',
                        '100 Chat Sessions',
                        'Unlimited Analysis',
                        'Premium Support',
                        'Early Access',
                      ],
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _purchaseSubscription('premium'),
                      recommended: true,
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'Credit Packs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _CreditPackCard(
                      title: 'Power Pack',
                      credits: 25,
                      price: '\$40',
                      onTap: () => _purchaseCredits('credits_25', 25),
                    ),

                    const SizedBox(height: 12),

                    _CreditPackCard(
                      title: 'Starter Pack',
                      credits: 10,
                      price: '\$15',
                      onTap: () => _purchaseCredits('credits_10', 10),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;
  final bool recommended;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.features,
    required this.color,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          elevation: recommended ? 4 : 0,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: color),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 20, color: color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'BEST VALUE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CreditPackCard extends StatelessWidget {
  final String title;
  final int credits;
  final String price;
  final VoidCallback onTap;

  const _CreditPackCard({
    required this.title,
    required this.credits,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF6366F1),
          child: Icon(Icons.add_shopping_cart, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$credits Credits'),
        trailing: Text(
          price,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// === PROFILE SCREEN ===

class ProfileScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const ProfileScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(
            radius: 50,
            backgroundColor: Color(0xFF6366F1),
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            widget.user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Center(
            child: Chip(
              label: Text(
                '${widget.user.tier.toString().split('.').last.toUpperCase()} TIER',
              ),
              backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
            ),
          ),

          const SizedBox(height: 32),

          // Credits Overview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Credits',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _CreditRow(
                    label: 'Trial Credits',
                    value: widget.user.trialsRemaining.toString(),
                  ),
                  _CreditRow(
                    label: 'Coach Creation',
                    value: widget.user.coachCreationCredits.toString(),
                  ),
                  _CreditRow(
                    label: 'Chat Sessions',
                    value: widget.user.chatCredits.toString(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'About AI Coach',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Democratizing personal coaching through AI. The right guidance at the right moment can change everything.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String value;

  const _CreditRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
