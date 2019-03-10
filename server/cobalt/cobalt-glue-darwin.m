#include "cobalt.h"

#import <CoreBluetooth/CoreBluetooth.h>

static NSArray<CBUUID *> *cobalt_strv_to_uuid_array(gchar **uuids, int uuidsLength);

@interface CobaltPeripheralManagerHandle : NSObject <CBCentralManagerDelegate> {
  @public CobaltPeripheralManager *wrapper;
  @public CBCentralManager *impl;
}
@end

@interface CobaltPeripheralHandle : NSObject <CBPeripheralDelegate> {
  @public CobaltPeripheral *wrapper;
  @public CBPeripheral *impl;
}

- (instancetype)initWithImplementation:(CBPeripheral *)theImpl
                               manager:(CobaltPeripheralManager *)manager;

@end

@implementation CobaltPeripheralManagerHandle

- (instancetype)initWithWrapper:(CobaltPeripheralManager *)theWrapper {
  self = [super init];

  if (self != nil) {
    wrapper = theWrapper;
    impl = nil;
  }

  return self;
}

- (void)start {
  impl = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
  _cobalt_peripheral_manager_on_state_changed(wrapper, impl.state);
}

- (void)startScan:(NSArray<CBUUID *> *)uuids {
  [impl scanForPeripheralsWithServices:uuids
                               options:@{}];
}

- (void)stopScan {
  [impl stopScan];
  _cobalt_peripheral_manager_on_scan_stopped(wrapper);
}

- (void)connectPeripheral:(CobaltPeripheralHandle *)peripheralHandle {
  [impl connectPeripheral:peripheralHandle->impl
                  options:nil];
}

- (void)cancelPeripheralConnection:(CobaltPeripheralHandle *)peripheralHandle {
  [impl cancelPeripheralConnection:peripheralHandle->impl];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  _cobalt_peripheral_manager_on_state_changed(wrapper, impl.state);
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
  CobaltPeripheralHandle *peripheralHandle = [[CobaltPeripheralHandle alloc] initWithImplementation:peripheral
                                                                                            manager:wrapper];
  _cobalt_peripheral_manager_on_scan_match_found(wrapper, peripheralHandle->wrapper);
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
  _cobalt_peripheral_manager_on_connect_success(wrapper, (__bridge gpointer) peripheral);
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                     error:(NSError *)error {
  _cobalt_peripheral_manager_on_connect_failure(wrapper, (__bridge gpointer) peripheral, error.localizedDescription.UTF8String);
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                  error:(NSError *)error {
  _cobalt_peripheral_manager_on_disconnect(wrapper, (__bridge gpointer) peripheral, error.localizedDescription.UTF8String);
}

@end

gpointer _cobalt_peripheral_manager_open(CobaltPeripheralManager *wrapper) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *handle = [[CobaltPeripheralManagerHandle alloc] initWithWrapper:wrapper];
    dispatch_async(dispatch_get_main_queue(), ^{
      [handle start];
    });
    return (__bridge_retained gpointer) handle;
  }
}

void _cobalt_peripheral_manager_close(CobaltPeripheralManager *wrapper, gpointer opaqueHandle) {
  @autoreleasepool {
    g_object_ref(wrapper);
    dispatch_async(dispatch_get_main_queue(), ^{
      CobaltPeripheralManagerHandle *handle = (__bridge_transfer CobaltPeripheralManagerHandle *) opaqueHandle;
      handle = nil;
      g_object_unref(wrapper);
    });
  }
}

void _cobalt_peripheral_manager_start_scan(CobaltPeripheralManager *wrapper, gchar **uuids, int uuidsLength) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;

    NSArray *uuidValues = cobalt_strv_to_uuid_array(uuids, uuidsLength);

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle startScan:uuidValues];
    });
  }
}

void _cobalt_peripheral_manager_stop_scan(CobaltPeripheralManager *wrapper) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle stopScan];
    });
  }
}

void _cobalt_peripheral_manager_connect_peripheral(CobaltPeripheralManager *wrapper, CobaltPeripheral *peripheral) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) peripheral->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle connectPeripheral:peripheralHandle];
    });
  }
}

void _cobalt_peripheral_manager_cancel_peripheral_connection(CobaltPeripheralManager *wrapper, CobaltPeripheral *peripheral) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) peripheral->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle cancelPeripheralConnection:peripheralHandle];
    });
  }
}

@implementation CobaltPeripheralHandle

- (instancetype)initWithImplementation:(CBPeripheral *)theImpl
                               manager:(CobaltPeripheralManager *)manager {
  self = [super init];

  if (self != nil) {
    wrapper = cobalt_peripheral_new(manager);
    impl = theImpl;

    wrapper->handle = (__bridge_retained gpointer) self;

    impl.delegate = self;
  }

  return self;
}

- (void)startServiceDiscovery:(NSArray<CBUUID *> *)serviceUUIDs {
  [impl discoverServices:serviceUUIDs];
}

- (void)startIncludedServiceDiscovery:(NSArray<CBUUID *> *)includedServiceUUIDs
                           forService:(CBService *)service {
  [impl discoverIncludedServices:includedServiceUUIDs
                      forService:service];
}

- (void)startCharacteristicDiscovery:(NSArray<CBUUID *> *)characteristicUUIDs
                          forService:(CBService *)service {
  [impl discoverCharacteristics:characteristicUUIDs
                     forService:service];
}

- (void)startDescriptorDiscovery:(CBCharacteristic *)characteristic {
  [impl discoverDescriptorsForCharacteristic:characteristic];
}

- (void)startCharacteristicRead:(CBCharacteristic *)characteristic {
  [impl readValueForCharacteristic:characteristic];
}

- (void)startCharacteristicWrite:(CBCharacteristic *)characteristic
                           value:(NSData *)data
                            type:(CBCharacteristicWriteType)type {
  [impl writeValue:data
 forCharacteristic:characteristic
              type:type];

  if (type == CBCharacteristicWriteWithoutResponse) {
    _cobalt_peripheral_on_characteristic_value_write_success(wrapper, (__bridge gpointer) characteristic);
  }
}

-  (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error {
  if (error == nil) {
    GeeArrayList *services = gee_array_list_new(COBALT_TYPE_SERVICE,
        (GBoxedCopyFunc) g_object_ref, (GDestroyNotify) g_object_unref,
        NULL, NULL, NULL);

    for (CBService *handle in peripheral.services) {
      const gchar *uuid = handle.UUID.UUIDString.UTF8String;
      CobaltService *service = cobalt_service_new((__bridge_retained gpointer) handle, uuid, wrapper);
      gee_abstract_collection_add(GEE_ABSTRACT_COLLECTION(services), service);
    }

    _cobalt_peripheral_on_service_discovery_success(wrapper, services);
  } else {
    _cobalt_peripheral_on_service_discovery_failure(wrapper, error.localizedDescription.UTF8String);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverIncludedServicesForService:(CBService *)service
                                error:(NSError *)error {
  if (error == nil) {
    GeeArrayList *services = gee_array_list_new(COBALT_TYPE_SERVICE,
        (GBoxedCopyFunc) g_object_ref, (GDestroyNotify) g_object_unref,
        NULL, NULL, NULL);

    for (CBService *handle in service.includedServices) {
      const gchar *uuid = handle.UUID.UUIDString.UTF8String;
      CobaltService *service = cobalt_service_new((__bridge_retained gpointer) handle, uuid, wrapper);
      gee_abstract_collection_add(GEE_ABSTRACT_COLLECTION(services), service);
    }

    _cobalt_peripheral_on_included_service_discovery_success(wrapper, (__bridge gpointer) service, services);
  } else {
    _cobalt_peripheral_on_included_service_discovery_failure(wrapper, (__bridge gpointer) service, error.localizedDescription.UTF8String);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
                               error:(NSError *)error {
  if (error == nil) {
    GeeArrayList *characteristics = gee_array_list_new(COBALT_TYPE_CHARACTERISTIC,
        (GBoxedCopyFunc) g_object_ref, (GDestroyNotify) g_object_unref,
        NULL, NULL, NULL);

    for (CBCharacteristic *handle in service.characteristics) {
      const gchar *uuid = handle.UUID.UUIDString.UTF8String;
      CobaltCharacteristic *characteristic = cobalt_characteristic_new((__bridge_retained gpointer) handle, uuid, wrapper);
      gee_abstract_collection_add(GEE_ABSTRACT_COLLECTION(characteristics), characteristic);
    }

    _cobalt_peripheral_on_characteristic_discovery_success(wrapper, (__bridge gpointer) service, characteristics);
  } else {
    _cobalt_peripheral_on_characteristic_discovery_failure(wrapper, (__bridge gpointer) service, error.localizedDescription.UTF8String);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic
                                  error:(NSError *)error {
  if (error == nil) {
    GeeArrayList *descriptors = gee_array_list_new(COBALT_TYPE_DESCRIPTOR,
        (GBoxedCopyFunc) g_object_ref, (GDestroyNotify) g_object_unref,
        NULL, NULL, NULL);

    for (CBDescriptor *handle in characteristic.descriptors) {
      const gchar *uuid = handle.UUID.UUIDString.UTF8String;
      CobaltDescriptor *descriptor = cobalt_descriptor_new((__bridge_retained gpointer) handle, uuid);
      gee_abstract_collection_add(GEE_ABSTRACT_COLLECTION(descriptors), descriptor);
    }

    _cobalt_peripheral_on_descriptor_discovery_success(wrapper, (__bridge gpointer) characteristic, descriptors);
  } else {
    _cobalt_peripheral_on_descriptor_discovery_failure(wrapper, (__bridge gpointer) characteristic, error.localizedDescription.UTF8String);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
                          error:(NSError *)error {
  if (error == nil) {
    NSData *data = characteristic.value;
    _cobalt_peripheral_on_characteristic_value_updated(wrapper, (__bridge gpointer) characteristic, g_bytes_new(data.bytes, data.length), NULL);
  } else {
    _cobalt_peripheral_on_characteristic_value_updated(wrapper, (__bridge gpointer) characteristic, NULL, error.localizedDescription.UTF8String);
  }
}

- (void)peripheral:(CBPeripheral *)peripheral
didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
                         error:(NSError *)error {
  NSLog(@"didWriteValueForCharacteristic error=%@", error);
  if (error == nil) {
    _cobalt_peripheral_on_characteristic_value_write_success(wrapper, (__bridge gpointer) characteristic);
  } else {
    _cobalt_peripheral_on_characteristic_value_write_failure(wrapper, (__bridge gpointer) characteristic, error.localizedDescription.UTF8String);
  }
}

@end

gpointer _cobalt_peripheral_get_implementation(CobaltPeripheral *wrapper) {
  CobaltPeripheralHandle *handle = (__bridge CobaltPeripheralHandle *) wrapper->handle;
  return (__bridge gpointer) handle->impl;
}

void _cobalt_peripheral_start_service_discovery(CobaltPeripheral *wrapper, gchar **uuids, int uuidsLength) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    NSArray *uuidValues = cobalt_strv_to_uuid_array(uuids, uuidsLength);

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startServiceDiscovery:uuidValues];
    });
  }
}

void _cobalt_peripheral_start_included_service_discovery(CobaltPeripheral *wrapper, CobaltService *serviceWrapper, gchar **uuids, int uuidsLength) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    CBService *service = (__bridge CBService *) cobalt_attribute_get_handle(COBALT_ATTRIBUTE(serviceWrapper));
    NSArray *uuidValues = cobalt_strv_to_uuid_array(uuids, uuidsLength);

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startIncludedServiceDiscovery:uuidValues
                                           forService:service];
    });
  }
}

void _cobalt_peripheral_start_characteristic_discovery(CobaltPeripheral *wrapper, CobaltService *serviceWrapper, gchar **uuids, int uuidsLength) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    CBService *service = (__bridge CBService *) cobalt_attribute_get_handle(COBALT_ATTRIBUTE(serviceWrapper));
    NSArray *uuidValues = cobalt_strv_to_uuid_array(uuids, uuidsLength);

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startCharacteristicDiscovery:uuidValues
                                          forService:service];
    });
  }
}

void _cobalt_peripheral_start_descriptor_discovery(CobaltPeripheral *wrapper, CobaltCharacteristic *characteristicWrapper) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    CBCharacteristic *characteristic = (__bridge CBCharacteristic *) cobalt_attribute_get_handle(COBALT_ATTRIBUTE(characteristicWrapper));

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startDescriptorDiscovery:characteristic];
    });
  }
}

void _cobalt_peripheral_start_characteristic_read(CobaltPeripheral *wrapper, CobaltCharacteristic *characteristicWrapper) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    CBCharacteristic *characteristic = (__bridge CBCharacteristic *) cobalt_attribute_get_handle(COBALT_ATTRIBUTE(characteristicWrapper));

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startCharacteristicRead:characteristic];
    });
  }
}

void _cobalt_peripheral_start_characteristic_write(CobaltPeripheral *wrapper, CobaltCharacteristic *characteristicWrapper, GBytes *val, CobaltCharacteristicWriteType write_type) {
  @autoreleasepool {
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) wrapper->handle;

    CBCharacteristic *characteristic = (__bridge CBCharacteristic *) cobalt_attribute_get_handle(COBALT_ATTRIBUTE(characteristicWrapper));
    gsize val_size;
    gconstpointer val_data = g_bytes_get_data(val, &val_size);
    NSData *data = [NSData dataWithBytes:val_data
                                  length:val_size];

    dispatch_async(dispatch_get_main_queue(), ^{
      [peripheralHandle startCharacteristicWrite:characteristic
                                           value:data
                                            type:(CBCharacteristicWriteType) write_type];
    });
  }
}

void _cobalt_attribute_close(gpointer opaqueHandle) {
  @autoreleasepool {
    CBService *handle = (__bridge_transfer CBService *) opaqueHandle;
    handle = nil;
  }
}

static NSArray<CBUUID *> *
cobalt_strv_to_uuid_array(gchar **uuids, int uuidsLength) {
  if (uuids == NULL)
    return nil;

  NSMutableArray *result = [NSMutableArray arrayWithCapacity:uuidsLength];
  for (int i = 0; i != uuidsLength; i++) {
    [result addObject:[CBUUID UUIDWithString:[NSString stringWithUTF8String:uuids[i]]]];
  }
  return result;
}
