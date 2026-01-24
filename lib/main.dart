import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const DictionaryApp());
}

class DictionaryApp extends StatefulWidget {
  const DictionaryApp({super.key});

  @override
  State<DictionaryApp> createState() => _DictionaryAppState();
}

class _DictionaryAppState extends State<DictionaryApp> {
  bool dark = false;
  bool firstRun = true;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    dark = prefs.getBool("dark") ?? false;
    firstRun = prefs.getBool("firstRun") ?? true;
    setState(() => loaded = true);
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => dark = !dark);
    await prefs.setBool("dark", dark);
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("firstRun", false);
    setState(() => firstRun = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: firstRun
          ? OnboardingScreen(onDone: _finishOnboarding)
          : DictionaryHome(
              isDark: dark,
              onToggleTheme: _toggleTheme,
            ),
    );
  }
}

/* ---------------- ONBOARDING ---------------- */

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book, size: 96),
            const SizedBox(height: 24),
            const Text(
              "Welcome to Modern Dictionary",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Search words, save favorites, hear pronunciation, and grow your vocabulary daily.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: onDone,
              child: const Text("Get Started"),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- HOME ---------------- */

class DictionaryHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const DictionaryHome({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<DictionaryHome> createState() => _DictionaryHomeState();
}

class _DictionaryHomeState extends State<DictionaryHome> {
  final controller = TextEditingController();
  final tts = FlutterTts();

  bool loading = false;
  String? error;
  List<dynamic>? meanings;
  String? word;

  List<String> history = [];
  List<String> favorites = [];

  String? wordOfDay;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadWordOfDay();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      history = prefs.getStringList("history") ?? [];
      favorites = prefs.getStringList("favorites") ?? [];
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("history", history);
    await prefs.setStringList("favorites", favorites);
  }

  Future<void> _loadWordOfDay() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final savedDate = prefs.getString("wotd_date");
    final savedWord = prefs.getString("wotd_word");

    if (savedDate == today && savedWord != null) {
      setState(() => wordOfDay = savedWord);
    } else {
      const words = ["curious", "brilliant", "elevate", "serenity", "explore"];
      final w = (words..shuffle()).first;
      await prefs.setString("wotd_date", today);
      await prefs.setString("wotd_word", w);
      setState(() => wordOfDay = w);
    }
  }

  Future<void> search(String q) async {
    setState(() {
      loading = true;
      error = null;
      meanings = null;
      word = null;
    });

    try {
      final url = Uri.parse(
        "https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(q)}",
      );
      final res = await http.get(url);

      if (res.statusCode != 200) throw Exception();

      final data = jsonDecode(res.body);
      setState(() {
        word = data[0]["word"];
        meanings = data[0]["meanings"];

        if (!history.contains(word)) {
          history.insert(0, word!);
          if (history.length > 20) history.removeLast();
          _savePrefs();
        }
      });
    } catch (_) {
      setState(() {
        error = "No definition found. Try another word.";
      });
    } finally {
      setState(() => loading = false);
    }
  }

  void _toggleFavorite() {
    if (word == null) return;
    setState(() {
      if (favorites.contains(word)) {
        favorites.remove(word);
      } else {
        favorites.add(word!);
      }
      _savePrefs();
    });
  }

  void _speak() {
    if (word != null) {
      tts.speak(word!);
    }
  }

  void _openPanel(String title, List<String> items) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("Empty"))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(items[i]),
                        onTap: () {
                          Navigator.pop(context);
                          controller.text = items[i];
                          search(items[i]);
                        },
                      ),
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
      appBar: AppBar(
        title: const Text("Dictionary"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _openPanel("History", history),
          ),
          IconButton(
            icon: const Icon(Icons.star),
            onPressed: () => _openPanel("Favorites", favorites),
          ),
          if (word != null)
            IconButton(
              icon: Icon(
                favorites.contains(word) ? Icons.star : Icons.star_border,
              ),
              onPressed: _toggleFavorite,
            ),
          IconButton(
            icon: Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (wordOfDay != null)
              Card(
                child: ListTile(
                  title: const Text("Word of the Day"),
                  subtitle: Text(wordOfDay!),
                  trailing: const Icon(Icons.trending_up),
                  onTap: () {
                    controller.text = wordOfDay!;
                    search(wordOfDay!);
                  },
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Search a word",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    final q = controller.text.trim();
                    if (q.isNotEmpty) search(q);
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) search(v.trim());
              },
            ),
            const SizedBox(height: 20),
            if (loading) const CircularProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (!loading && meanings != null) Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    return ListView(
      children: [
        Row(
          children: [
            Text(
              word!,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.volume_up),
              onPressed: _speak,
            ),
            const Spacer(),
            Icon(
              favorites.contains(word) ? Icons.star : Icons.star_border,
              color: Colors.amber,
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final m in meanings!) _meaningCard(m),
      ],
    );
  }

  Widget _meaningCard(dynamic m) {
    final defs = m["definitions"] as List;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m["partOfSpeech"],
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            for (final d in defs.take(3)) ...[
              Text("• ${d["definition"]}"),
              if (d["example"] != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 6),
                  child: Text(
                    "\"${d["example"]}\"",
                    style: const TextStyle(
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
