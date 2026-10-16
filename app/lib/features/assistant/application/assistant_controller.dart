import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/assistant/application/ai_providers.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/format/format.dart';

/// Where an optional online AI answer to an exchange stands.
enum AiStatus { pending, answered, offline, busy, refused }

class AiOutcome {
  const AiOutcome(this.status, [this.text]);

  final AiStatus status;

  /// Generated text that passed the on-device check (only when answered).
  final String? text;
}

/// One question and its answer. [question] is what the user typed, or null
/// for a follow-up answer after they chose a station.
class AssistantExchange {
  const AssistantExchange({
    required this.answer,
    this.question,
    this.chosenStationId,
    this.ai,
  });

  final String? question;

  /// The station picked to complete a clarification (shown as the user's
  /// turn).
  final String? chosenStationId;
  final AssistantAnswer answer;

  /// Online AI result, only for questions the offline assistant could not
  /// understand at all.
  final AiOutcome? ai;

  AssistantExchange withAi(AiOutcome outcome) => AssistantExchange(
    answer: answer,
    question: question,
    chosenStationId: chosenStationId,
    ai: outcome,
  );
}

/// The conversation, newest last. Memory only: questions are never stored or
/// sent anywhere (offline assistant, M9).
class AssistantController extends Notifier<List<AssistantExchange>> {
  @override
  List<AssistantExchange> build() => const [];

  /// Longest question accepted (docs/security.md: input capped).
  static const maxLength = 500;

  AssistantContext _context() {
    final now = ref.read(clockProvider)();
    return AssistantContext(
      dayType: dayTypeOf(now),
      minuteOfDay: now.hour * 60 + now.minute,
    );
  }

  /// Answers offline first. Only if the assistant did not understand the
  /// question at all (`unknown`), an AI answer is asked for in the
  /// background when a gateway is configured and the user allows it; the
  /// offline answer is shown meanwhile and never replaced.
  void ask(String text, {String locale = 'en'}) {
    final q = text.trim();
    if (q.isEmpty) return;
    final capped = q.length > maxLength ? q.substring(0, maxLength) : q;
    final services = ref.read(metroServicesProvider);
    final answer = services.assistant.ask(capped, context: _context());
    final gateway = ref.read(aiGatewayProvider);
    final wantsAi =
        answer.kind == AnswerKind.unknown &&
        gateway.configured &&
        ref.read(onlineAiEnabledProvider) &&
        ref.read(remoteConfigProvider).flags.onlineAi;
    final exchange = AssistantExchange(
      question: capped,
      answer: answer,
      ai: wantsAi ? const AiOutcome(AiStatus.pending) : null,
    );
    state = [...state, exchange];
    if (wantsAi) unawaited(_askAi(exchange, capped, locale, gateway));
  }

  Future<void> _askAi(
    AssistantExchange exchange,
    String question,
    String locale,
    AiGateway gateway,
  ) async {
    final services = ref.read(metroServicesProvider);
    final result = await gateway.ask(
      AiRequest(
        question: question,
        locale: locale == 'hi' ? 'hi' : 'en',
        grounding: AiGrounding.build(
          services.snapshot,
          services.assistant.understand(question),
        ),
        datasetVersion: services.datasetVersion,
      ),
    );
    final outcome = switch (result) {
      AiAnswer(:final text) => AiOutcome(AiStatus.answered, text),
      AiRefused() => const AiOutcome(AiStatus.refused),
      AiUnavailable(:final reason) =>
        reason == 'rate limited' || reason == 'not configured'
            ? const AiOutcome(AiStatus.busy)
            : const AiOutcome(AiStatus.offline),
    };
    final i = state.indexWhere((e) => identical(e, exchange));
    if (i < 0) return; // the conversation was cleared meanwhile
    state = [...state]..[i] = exchange.withAi(outcome);
  }

  /// Completes the clarification of [exchange] with [stationId] (a chip or a
  /// station picked in the picker).
  void choose(AssistantExchange exchange, String stationId) {
    final a = exchange.answer;
    final q = a.question;
    final slot = a.slot;
    if (q == null || slot == null) return;
    final services = ref.read(metroServicesProvider);
    final answer = services.assistant.answer(
      q.withSlot(slot, stationId),
      context: _context(),
    );
    state = [
      ...state,
      AssistantExchange(answer: answer, chosenStationId: stationId),
    ];
  }

  void clear() => state = const [];
}

final assistantProvider =
    NotifierProvider<AssistantController, List<AssistantExchange>>(
      AssistantController.new,
    );
