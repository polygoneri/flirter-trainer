// lib/models/enums.dart
import 'package:flutter/material.dart';

/// Vibe styles for suggestion generation.
enum Vibe { mix, charming, flirty, assertive, sharp, effortless, neutral }

/// User goals for matching / conversation intent.
enum UserGoal { hookup, newFriends, longTerm, shortTerm }

/// Flow types for suggestion generation.
enum FlowType { openingLine, respondMessage, igniteChat }

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
      default:
        throw ArgumentError('Unknown FlowType value: $v');
    }
  }
}

extension UserGoalX on UserGoal {
  /// String value used in storage / API.
  String get value {
    switch (this) {
      case UserGoal.hookup:
        return 'hookup';
      case UserGoal.newFriends:
        return 'new_friends';
      case UserGoal.longTerm:
        return 'long_term';
      case UserGoal.shortTerm:
        return 'short_term';
    }
  }

  /// Human label for UI.
  String get label {
    switch (this) {
      case UserGoal.hookup:
        return 'Hookup';
      case UserGoal.newFriends:
        return 'New Friends';
      case UserGoal.longTerm:
        return 'Long Term';
      case UserGoal.shortTerm:
        return 'Short Term';
    }
  }

  static UserGoal fromValue(String v) {
    switch (v) {
      case 'hookup':
        return UserGoal.hookup;
      case 'new_friends':
        return UserGoal.newFriends;
      case 'long_term':
        return UserGoal.longTerm;
      case 'short_term':
        return UserGoal.shortTerm;
      default:
        throw ArgumentError('Unknown UserGoal value: $v');
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
      case Vibe.flirty:
        return 'flirty';
      case Vibe.assertive:
        return 'assertive';
      case Vibe.sharp:
        return 'sharp';
      case Vibe.effortless:
        return 'effortless';
      case Vibe.neutral:
        return 'neutral';
    }
  }

  /// Human label for UI.
  String get label {
    switch (this) {
      case Vibe.mix:
        return 'Mix';
      case Vibe.charming:
        return 'Charming';
      case Vibe.flirty:
        return 'Flirty';
      case Vibe.assertive:
        return 'Assertive';
      case Vibe.sharp:
        return 'Sharp';
      case Vibe.effortless:
        return 'Effortless';
      case Vibe.neutral:
        return 'neutral';
    }
  }

  static Vibe fromValue(String v) {
    switch (v) {
      case 'mix':
        return Vibe.mix;
      case 'charming':
        return Vibe.charming;
      case 'flirty':
        return Vibe.flirty;
      case 'assertive':
        return Vibe.assertive;
      case 'sharp':
        return Vibe.sharp;
      case 'effortless':
        return Vibe.effortless;
      case 'neutral':
        return Vibe.neutral;
      default:
        throw ArgumentError('Unknown Vibe value: $v');
    }
  }
}

/// Dropdown helpers so UI code stays tiny.
class DropdownModels {
  static List<DropdownMenuItem<String>> userGoalItems() => UserGoal.values
      .map(
        (e) => DropdownMenuItem<String>(value: e.value, child: Text(e.label)),
      )
      .toList(growable: false);

  static List<DropdownMenuItem<String>> vibeItems() => Vibe.values
      .map(
        (e) => DropdownMenuItem<String>(value: e.value, child: Text(e.label)),
      )
      .toList(growable: false);

  /// Flow items (no "Determine by AI" here, that’s a special UI-only option)
  static List<DropdownMenuItem<String>> flowItems() => FlowType.values
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
