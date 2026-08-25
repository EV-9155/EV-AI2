import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const EVApp());

class EVApp extends StatelessWidget {
  const EVApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'EV',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
    home: const ChatPage(),
  );
}

class Message {
  final String role;
  final String text;
  Message(this.role, this.text);
  Map<String,dynamic> toJson() => {'role': role, 'text': text};
  factory Message.fromJson(Map<String,dynamic> x) =>
      Message(x['role'] ?? 'assistant', x['text'] ?? '');
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final speech = stt.SpeechToText();
  final tts = FlutterTts();
  final messages = <Message>[];
  String backend = '';
  bool listening = false, loading = false, autoVoice = true;

  @override
  void initState() {
    super.initState();
    load();
    setupVoice();
  }

  Future<void> setupVoice() async {
    await tts.setLanguage('ar-EG');
    await tts.setSpeechRate(0.48);
    await tts.setPitch(1.08);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('messages');
    setState(() {
      backend = p.getString('backend') ?? '';
      autoVoice = p.getBool('autoVoice') ?? true;
      if (raw != null) {
        messages.addAll((jsonDecode(raw) as List)
          .map((e) => Message.fromJson(e)));
      }
      if (messages.isEmpty) {
        messages.add(Message('assistant',
          'أهلاً 👋 أنا EV. اتكلم معايا عادي بالمصري.'));
      }
    });
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('messages',
      jsonEncode(messages.map((x) => x.toJson()).toList()));
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || loading) return;
    input.clear();
    setState(() {
      messages.add(Message('user', text));
      loading = true;
    });
    await save();
    down();

    if (backend.isEmpty) {
      setState(() {
        messages.add(Message('assistant',
          'الواجهة والصوت والذاكرة جاهزين. اربطي EV بمحرك AI من الإعدادات عشان تبدأ ترد بذكاء.'));
        loading = false;
      });
      await save();
      down();
      return;
    }

    try {
      final r = await http.post(
        Uri.parse(backend),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'assistant': 'EV',
          'language': 'ar-EG',
          'style': 'natural Egyptian Arabic',
          'message': text,
          'history': messages.map((m) => m.toJson()).toList(),
          'need_sources': true,
        }),
      ).timeout(const Duration(seconds: 60));

      final data = jsonDecode(r.body);
      final reply = (data['reply'] ?? 'مش قادرة أرد دلوقتي.').toString();
      setState(() => messages.add(Message('assistant', reply)));
      if (autoVoice) await tts.speak(reply);
    } catch (_) {
      setState(() => messages.add(Message('assistant',
        'حصلت مشكلة في الاتصال بالـAI. راجع عنوان الـBackend والإنترنت.')));
    } finally {
      setState(() => loading = false);
      await save();
      down();
    }
  }

  Future<void> voice() async {
    if (listening) {
      await speech.stop();
      setState(() => listening = false);
      return;
    }
    final ok = await speech.initialize(
      onStatus: (s) {
        if (s == 'done') setState(() => listening = false);
      },
      onError: (_) => setState(() => listening = false),
    );
    if (!ok) return;
    setState(() => listening = true);
    await speech.listen(
      localeId: 'ar_EG',
      listenMode: stt.ListenMode.dictation,
      onResult: (r) {
        setState(() => input.text = r.recognizedWords);
        if (r.finalResult) send();
      },
    );
  }

  void down() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
      }
    });
  }

  Future<void> settings() async {
    final c = TextEditingController(text: backend);
    bool av = autoVoice;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,18,18,MediaQuery.of(ctx).viewInsets.bottom+18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('إعدادات EV',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://example.com/chat',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            title: const Text('نطق الرد تلقائياً'),
            value: av,
            onChanged: (v) => setSheet(() => av = v),
          ),
          FilledButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.setString('backend', c.text.trim());
              await p.setBool('autoVoice', av);
              setState(() {
                backend = c.text.trim();
                autoVoice = av;
              });
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(child: Icon(Icons.auto_awesome)),
          SizedBox(width: 10),
          Text('EV'),
        ]),
        actions: [
          IconButton(onPressed: settings, icon: const Icon(Icons.settings)),
          IconButton(
            onPressed: () async {
              setState(() {
                messages
                  ..clear()
                  ..add(Message('assistant',
                    'محادثة جديدة 👋 أنا EV. نبدأ بإيه؟'));
              });
              await save();
            },
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final m = messages[i];
              final me = m.role == 'user';
              return Align(
                alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 700),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: me
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(m.text,
                    style: const TextStyle(fontSize: 16, height: 1.35)),
                ),
              );
            },
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8,6,8,8),
            child: Row(children: [
              IconButton.filledTonal(
                onPressed: voice,
                icon: Icon(listening ? Icons.stop : Icons.mic),
              ),
              const SizedBox(width: 5),
              Expanded(child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                onSubmitted: (_) => send(),
                decoration: InputDecoration(
                  hintText: 'اتكلم مع EV...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24)),
                ),
              )),
              const SizedBox(width: 5),
              IconButton.filled(
                onPressed: send,
                icon: const Icon(Icons.arrow_upward),
              ),
            ]),
          ),
        ),
      ]),
    ),
  );
}
