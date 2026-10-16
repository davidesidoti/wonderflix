/// Membri per iniziare una sala del match: chi l'ha aperta e almeno un amico
/// (come il plugin, spec P §6.4).
const matchMinMembers = 2;

/// Lo stesso id, con o senza trattini e maiuscole: il plugin usa il formato
/// "N" di Jellyfin.
String normalizeMatchId(String id) => id.replaceAll('-', '').toLowerCase();

/// Fasi di una sala del match (spec P §6.1).
enum MatchPhase {
  waiting('Waiting'),
  voting('Voting'),
  closed('Closed');

  const MatchPhase(this.wire);

  final String wire;

  /// Un valore sconosciuto vale [closed]: una sala che non capiamo non si usa.
  static MatchPhase fromWire(Object? raw) =>
      values.firstWhere((phase) => phase.wire == raw, orElse: () => closed);
}

/// Perché una sala si è chiusa (spec P §6.1).
enum MatchClosedReason {
  creatorLeft('CreatorLeft'),
  inactive('Inactive'),
  partyStarted('PartyStarted');

  const MatchClosedReason(this.wire);

  final String wire;

  /// `null` se manca o non lo conosciamo.
  static MatchClosedReason? fromWire(Object? raw) {
    for (final reason in values) {
      if (reason.wire == raw) return reason;
    }
    return null;
  }
}

/// Un membro della sala: quanti voti ha dato, mai quali.
class MatchMember {
  const MatchMember(
      {required this.userId, required this.name, required this.voted});

  factory MatchMember.fromJson(Map<String, dynamic> json) => MatchMember(
        userId: json['UserId'] as String,
        name: json['Name'] as String? ?? '',
        voted: (json['Voted'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String name;
  final int voted;
}

/// Un quasi match (spec P §6.3): quanti sì su quanti membri.
class MatchNearMatch {
  const MatchNearMatch(
      {required this.itemId, required this.yes, required this.of});

  factory MatchNearMatch.fromJson(Map<String, dynamic> json) => MatchNearMatch(
        itemId: json['ItemId'] as String,
        yes: (json['Yes'] as num).toInt(),
        of: (json['Of'] as num).toInt(),
      );

  final String itemId;
  final int yes;
  final int of;
}

/// Lo stato di una sala (spec P §6.4): dalle risposte e da `MatchUpdated`.
class MatchState {
  const MatchState({
    required this.roomId,
    required this.rev,
    required this.phase,
    required this.creatorId,
    required this.creatorName,
    this.members = const [],
    this.stack = const [],
    this.matches = const [],
    this.nearMatches = const [],
    this.closedReason,
    this.partyGroupId,
  });

  factory MatchState.fromJson(Map<String, dynamic> json) => MatchState(
        roomId: json['RoomId'] as String,
        rev: (json['Rev'] as num).toInt(),
        phase: MatchPhase.fromWire(json['Phase']),
        creatorId: json['CreatorId'] as String,
        creatorName: json['CreatorName'] as String? ?? '',
        members: [
          for (final raw in json['Members'] as List? ?? const [])
            MatchMember.fromJson(raw as Map<String, dynamic>),
        ],
        stack: [for (final raw in json['Stack'] as List? ?? const []) raw as String],
        matches: [
          for (final raw in json['Matches'] as List? ?? const []) raw as String,
        ],
        nearMatches: [
          for (final raw in json['NearMatches'] as List? ?? const [])
            MatchNearMatch.fromJson(raw as Map<String, dynamic>),
        ],
        closedReason: MatchClosedReason.fromWire(json['ClosedReason']),
        partyGroupId: json['PartyGroupId'] as String?,
      );

  final String roomId;

  /// Cresce a ogni cambio: lo stato con il numero più alto è il più recente.
  final int rev;
  final MatchPhase phase;
  final String creatorId;
  final String creatorName;

  /// Chi ha aperto per primo, poi nell'ordine d'ingresso.
  final List<MatchMember> members;

  /// La pila, uguale per tutti e nello stesso ordine.
  final List<String> stack;

  /// I match, nell'ordine in cui sono usciti.
  final List<String> matches;

  /// Solo quando tutti hanno votato tutta la pila.
  final List<MatchNearMatch> nearMatches;
  final MatchClosedReason? closedReason;

  /// Il party privato avviato da chi ha aperto la sala.
  final String? partyGroupId;

  bool isCreator(String userId) =>
      normalizeMatchId(userId) == normalizeMatchId(creatorId);

  bool hasMember(String userId) => members.any(
      (member) => normalizeMatchId(member.userId) == normalizeMatchId(userId));
}
