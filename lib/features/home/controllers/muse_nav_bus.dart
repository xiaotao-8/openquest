import 'package:flutter/foundation.dart';

/// Top-level navigation sections of the Muse-style sidebar.
enum MuseNavTab { chat, feed, ideas, goals, library }

/// Shared navigation state between the desktop sidebar (which renders the
/// 选项卡 / 空间 / 旁聊 sections) and the home page (which swaps its body
/// between the chat and the skeleton section pages).
class MuseNavBus {
  MuseNavBus._();
  static final MuseNavBus instance = MuseNavBus._();

  final ValueNotifier<MuseNavTab> tab = ValueNotifier(MuseNavTab.chat);

  /// One-shot request to open a conversation by id, raised from surfaces
  /// that cannot switch conversations themselves (e.g. a goal's linked
  /// conversation row). The home page listens, performs the switch, and
  /// clears the request back to null.
  final ValueNotifier<String?> conversationOpenRequest = ValueNotifier(null);

  void select(MuseNavTab value) {
    if (tab.value != value) tab.value = value;
  }

  void showChat() => select(MuseNavTab.chat);

  void requestOpenConversation(String id) {
    showChat();
    conversationOpenRequest.value = id;
  }
}
