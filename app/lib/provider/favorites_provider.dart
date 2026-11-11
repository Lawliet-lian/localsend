import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// This provider stores the list of favorite devices.
/// It automatically saves the list to the device's storage.
final favoritesProvider = ReduxProvider<FavoritesService, List<FavoriteDevice>>((ref) {
  return FavoritesService(ref.read(persistenceProvider));
});

class FavoritesService extends ReduxNotifier<List<FavoriteDevice>> {
  final PersistenceService _persistence;

  FavoritesService(this._persistence);

  @override
  List<FavoriteDevice> init() => _persistence.getFavorites();
}

/// Adds a favorite device.
class AddFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final FavoriteDevice device;

  AddFavoriteAction(this.device);

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final updated = List<FavoriteDevice>.unmodifiable([
      ...state,
      device,
    ]);
    await notifier._persistence.setFavorites(updated);
    return updated;
  }
}

/// Updates a favorite device.
class UpdateFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final FavoriteDevice device;

  UpdateFavoriteAction(this.device);

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((e) => e.id == device.id);
    if (index == -1) {
      // Unknown device
      await Future.microtask(() {});
      return state;
    }
    final updated = List<FavoriteDevice>.unmodifiable(
      <FavoriteDevice>[
        ...state,
      ]..replaceRange(index, index + 1, [device]),
    );
    await notifier._persistence.setFavorites(updated);
    return updated;
  }
}

/// Replace two user-confirmed identities with the old favorite's settings.
class RelinkFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final FavoriteDevice oldFavorite;
  final Device device;
  RelinkFavoriteAction({required this.oldFavorite, required this.device});

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((favorite) => favorite.id == oldFavorite.id);
    if (index < 0) throw StateError('Favorite no longer exists');
    final old = state[index];
    final updated = old.copyWith(
      fingerprint: device.fingerprint,
      ip: device.ip ?? old.ip,
      port: device.ip != null ? device.port : old.port,
      alias: old.customAlias ? old.alias : device.alias,
    );
    final result = List<FavoriteDevice>.unmodifiable([
      for (final favorite in state)
        if (favorite.id == old.id) updated else if (favorite.fingerprint.toLowerCase() != device.fingerprint.toLowerCase()) favorite,
    ]);
    await notifier._persistence.setFavorites(result);
    return result;
  }
}

/// Refreshes a saved device when it is rediscovered under the same identity.
class RefreshFavoriteFromDeviceAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final Device device;

  RefreshFavoriteFromDeviceAction(this.device);

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((favorite) => favorite.fingerprint.isNotEmpty && favorite.fingerprint == device.fingerprint);
    if (index == -1) return state;
    final favorite = state[index];
    final ip = device.ip;
    final updated = favorite.copyWith(
      ip: ip != null && ip.isNotEmpty ? ip : favorite.ip,
      port: ip != null && ip.isNotEmpty && device.port > 0 ? device.port : favorite.port,
      alias: favorite.customAlias ? favorite.alias : device.alias,
    );
    if (updated == favorite) return state;
    final favorites = List<FavoriteDevice>.of(state)..[index] = updated;
    final result = List<FavoriteDevice>.unmodifiable(favorites);
    await notifier._persistence.setFavorites(result);
    return result;
  }
}

/// Removes a favorite device.
class RemoveFavoriteAction extends AsyncReduxAction<FavoritesService, List<FavoriteDevice>> {
  final String deviceFingerprint;

  RemoveFavoriteAction({
    required this.deviceFingerprint,
  });

  @override
  Future<List<FavoriteDevice>> reduce() async {
    final index = state.indexWhere((e) => e.fingerprint == deviceFingerprint);
    if (index == -1) {
      // Unknown device
      return state;
    }
    final updated = List<FavoriteDevice>.unmodifiable(
      <FavoriteDevice>[
        ...state,
      ]..removeAt(index),
    );
    await notifier._persistence.setFavorites(updated);
    return updated;
  }
}
