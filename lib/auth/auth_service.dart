abstract class AuthService {
  /// The signed-in user's id, or null when signed out. Emits on every change.
  Stream<String?> uid();

  /// Throws on failure; returns normally if the user cancels.
  Future<void> signIn();

  Future<void> signOut();
}
