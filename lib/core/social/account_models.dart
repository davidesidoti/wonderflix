/// I canali dei contatti per il recupero (spec L §7.6): il nome è quello
/// delle rotte del plugin e delle voci della cassetta.
enum AccountChannel {
  discord('Discord'),
  email('Email');

  const AccountChannel(this.wire);

  final String wire;

  /// `null` per un canale che l'app non conosce.
  static AccountChannel? fromWire(Object? value) {
    for (final channel in values) {
      if (channel.wire == value) return channel;
    }
    return null;
  }
}

/// La password nuova più corta che l'app accetta (spec L §8): il plugin
/// vuole lo stesso minimo nel recupero.
const accountMinPasswordLength = 6;

/// Risposta di `GET Account/Contacts` e di `Confirm` (spec L §7.6): i canali
/// configurati sul server e i contatti verificati dell'utente.
class AccountContacts {
  const AccountContacts({
    this.discordAvailable = false,
    this.emailAvailable = false,
    this.discordName,
    this.email,
  });

  factory AccountContacts.fromJson(Map<String, dynamic> json) {
    final channels = json['Channels'] as Map<String, dynamic>? ?? const {};
    final discord = json['Discord'] as Map<String, dynamic>?;
    final email = json['Email'] as Map<String, dynamic>?;
    return AccountContacts(
      discordAvailable: channels['Discord'] == true,
      emailAvailable: channels['Email'] == true,
      discordName: discord?['Name'] as String?,
      email: email?['Address'] as String?,
    );
  }

  final bool discordAvailable;
  final bool emailAvailable;

  /// Il nome utente Discord collegato; `null` se non c'è.
  final String? discordName;

  /// L'email collegata, intera; `null` se non c'è.
  final String? email;

  /// Il canale è configurato sul server.
  bool isAvailable(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discordAvailable,
        AccountChannel.email => emailAvailable,
      };

  /// Il contatto collegato su [channel]; `null` se non c'è.
  String? contactOf(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discordName,
        AccountChannel.email => email,
      };
}
