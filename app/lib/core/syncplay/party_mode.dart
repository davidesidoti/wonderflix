/// Modalità di un watch party (spec F §6.4). In rete `Public`, `Friends`,
/// `Private`.
enum PartyMode {
  public('Public'),
  friends('Friends'),
  private('Private');

  const PartyMode(this.wire);

  final String wire;

  static PartyMode? fromWire(Object? value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
}
