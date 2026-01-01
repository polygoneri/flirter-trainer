import 'package:flutter/material.dart';

/// Flow types for suggestion generation.
enum FlowType { openingLine, respondMessage, igniteChat, makeAMove }

/// Vibe styles for suggestion generation.
enum Vibe {
  mix,
  charming,
  playful,
  funny,
  flirty,
  assertive,
  sharp,
  effortless,
}

extension FlowTypeX on FlowType {
  /// String value used in storage / API.
  String get value {
    switch (this) {
      case FlowType.openingLine:
        return 'opening_line';
      case FlowType.respondMessage:
        return 'respond_message';
      case FlowType.igniteChat:
        return 'ignite_chat';
      case FlowType.makeAMove:
        return 'make_a_move';
    }
  }

  /// Human label for UI.
  String get label {
    switch (this) {
      case FlowType.openingLine:
        return 'Opening line';
      case FlowType.respondMessage:
        return 'Reply to their last message';
      case FlowType.igniteChat:
        return 'Reignite chat';
      case FlowType.makeAMove:
        return 'Make a move';
    }
  }

  static FlowType fromValue(String v) {
    switch (v) {
      case 'opening_line':
        return FlowType.openingLine;
      case 'respond_message':
        return FlowType.respondMessage;
      case 'ignite_chat':
        return FlowType.igniteChat;
      case 'make_a_move':
        return FlowType.makeAMove;
      default:
        throw ArgumentError('Unknown FlowType value: $v');
    }
  }
}

extension VibeX on Vibe {
  /// String value used in storage / API.
  String get value {
    switch (this) {
      case Vibe.mix:
        return 'mix';
      case Vibe.charming:
        return 'charming';
      case Vibe.playful:
        return 'playful';
      case Vibe.funny:
        return 'funny';
      case Vibe.flirty:
        return 'flirty';
      case Vibe.assertive:
        return 'assertive';
      case Vibe.sharp:
        return 'sharp';
      case Vibe.effortless:
        return 'effortless';
    }
  }

  /// Human label for UI.
  String get label {
    switch (this) {
      case Vibe.mix:
        return 'Mix';
      case Vibe.charming:
        return 'Charming';
      case Vibe.playful:
        return 'Playful';
      case Vibe.funny:
        return 'Funny';
      case Vibe.flirty:
        return 'Flirty';
      case Vibe.assertive:
        return 'Assertive';
      case Vibe.sharp:
        return 'Sharp';
      case Vibe.effortless:
        return 'Effortless';
    }
  }

  static Vibe fromValue(String v) {
    switch (v) {
      case 'mix':
        return Vibe.mix;
      case 'charming':
        return Vibe.charming;
      case 'playful':
        return Vibe.playful;
      case 'funny':
        return Vibe.funny;
      case 'flirty':
        return Vibe.flirty;
      case 'assertive':
        return Vibe.assertive;
      case 'sharp':
        return Vibe.sharp;
      case 'effortless':
        return Vibe.effortless;
      default:
        throw ArgumentError('Unknown Vibe value: $v');
    }
  }
}

/// Dropdown helpers so UI code stays tiny.
class DropdownModels {
  static List<DropdownMenuItem<String>> flowItems() => FlowType.values
      .map(
        (e) => DropdownMenuItem<String>(value: e.value, child: Text(e.label)),
      )
      .toList(growable: false);

  static List<DropdownMenuItem<String>> vibeItems() => Vibe.values
      .map(
        (e) => DropdownMenuItem<String>(value: e.value, child: Text(e.label)),
      )
      .toList(growable: false);
}

enum TagOption {
  witty,
  smart,
  flirty,
  funny,
  trying_to_be_funny,
  charming,
  romantic,
  cringy,
  flat,
  sexy_in_a_good_way,
  slizzy,
  too_direct,
  too_long,
  too_much_effort,
  emoji_not_neccery,
  not_give_continuation,
  bingo,
  generic,
  off_topic,
  too_sexual,
  inappropriate,
  creepy,
  sweet,
  looks_ai_not_human,
  no_refernce_to_images,
  not_learning_from_images,
  overly_interested,
  too_eager,
}
