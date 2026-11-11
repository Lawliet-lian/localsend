import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockPersistenceService persistenceService;

  setUp(() {
    persistenceService = MockPersistenceService();
  });

  test('Should add a favorite device', () async {
    final service = ReduxNotifier.test(
      redux: FavoritesService(persistenceService),
    );

    expect(service.state, []);

    final device = _createDevice('1');

    await service.dispatchAsync(AddFavoriteAction(device));

    expect(service.state, [device]);
    verify(persistenceService.setFavorites([device]));
  });

  test('Should update a favorite device', () async {
    final initialDevice = _createDevice('1', alias: 'A');
    final service = ReduxNotifier.test(
      redux: FavoritesService(persistenceService),
      initialState: [initialDevice],
    );

    // Sanity check
    expect(service.state, [initialDevice]);
    expect(service.state.first.alias, 'A');

    final updatedDevice = _createDevice('1', alias: 'B');
    await service.dispatchAsync(UpdateFavoriteAction(updatedDevice));

    expect(service.state, [updatedDevice]);
    expect(service.state.first.alias, 'B');
    verify(persistenceService.setFavorites([updatedDevice]));
  });

  test('Should not update a favorite device if unknown id', () async {
    final initialDevice = _createDevice('1', alias: 'A');
    final service = ReduxNotifier.test(
      redux: FavoritesService(persistenceService),
      initialState: [initialDevice],
    );

    // Sanity check
    expect(service.state, [initialDevice]);
    expect(service.state.first.alias, 'A');

    final updatedDevice = _createDevice('2', alias: 'B');
    await service.dispatchAsync(UpdateFavoriteAction(updatedDevice));

    expect(service.state, [initialDevice]);
    expect(service.state.first.alias, 'A');
    verifyNever(persistenceService.setFavorites(any));
  });

  test('Rediscovery updates the address while preserving a custom alias', () async {
    final initial = _createDevice('1').copyWith(customAlias: true, alias: 'Friend');
    final service = ReduxNotifier.test(redux: FavoritesService(persistenceService), initialState: [initial]);
    final discovered = Device.empty.copyWith(fingerprint: '123', ip: '192.168.1.42', port: 53318, alias: 'New name');

    await service.dispatchAsync(RefreshFavoriteFromDeviceAction(discovered));

    expect(service.state.single.ip, '192.168.1.42');
    expect(service.state.single.port, 53318);
    expect(service.state.single.alias, 'Friend');
    verify(persistenceService.setFavorites(service.state)).called(1);
    await service.dispatchAsync(RefreshFavoriteFromDeviceAction(discovered));
    verifyNever(persistenceService.setFavorites(any));
  });

  test('Rediscovery only updates the matching fingerprint', () async {
    final initial = _createDevice('1');
    final service = ReduxNotifier.test(redux: FavoritesService(persistenceService), initialState: [initial]);
    await service.dispatchAsync(RefreshFavoriteFromDeviceAction(Device.empty.copyWith(fingerprint: 'other', ip: '192.168.1.42', port: 123)));
    expect(service.state.single, initial);
    verifyNever(persistenceService.setFavorites(any));
    await service.dispatchAsync(
      RefreshFavoriteFromDeviceAction(Device.empty.copyWith(fingerprint: '123', ip: '192.168.1.42', port: 456, alias: 'Updated')),
    );
    expect(service.state.single.alias, 'Updated');
    expect(service.state.single.ip, '192.168.1.42');
    expect(service.state.single.port, 456);
  });

  test('Should delete favorite device', () async {
    final initialDevice = _createDevice('1', fingerprint: '111');
    final service = ReduxNotifier.test(
      redux: FavoritesService(persistenceService),
      initialState: [initialDevice],
    );

    // Sanity check
    expect(service.state, [initialDevice]);

    await service.dispatchAsync(RemoveFavoriteAction(deviceFingerprint: '111'));

    expect(service.state, []);
    verify(persistenceService.setFavorites([]));
  });

  test('Should not delete favorite device if unknown fingerprint', () async {
    final initialDevice = _createDevice('1', fingerprint: '111');
    final service = ReduxNotifier.test(
      redux: FavoritesService(persistenceService),
      initialState: [initialDevice],
    );

    // Sanity check
    expect(service.state, [initialDevice]);

    await service.dispatchAsync(RemoveFavoriteAction(deviceFingerprint: '222'));

    expect(service.state, [initialDevice]);
    verifyNever(persistenceService.setFavorites(any));
  });
}

FavoriteDevice _createDevice(
  String id, {
  String fingerprint = '123',
  String alias = 'A',
}) {
  return FavoriteDevice(
    id: id,
    fingerprint: fingerprint,
    ip: '1.2.3.4',
    port: 123,
    alias: alias,
  );
}
