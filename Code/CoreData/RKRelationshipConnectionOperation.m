//
//  RKRelationshipConnectionOperation.m
//  RestKit
//
//  Created by Blake Watters on 7/12/12.
//  Copyright (c) 2012 RestKit. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <CoreData/CoreData.h>
#import "RKRelationshipConnectionOperation.h"
#import "RKConnectionDescription.h"
#import "RKEntityMapping.h"
#import "RKLog.h"
#import "RKManagedObjectCaching.h"
#import "RKObjectMappingMatcher.h"
#import "RKErrors.h"
#import "RKObjectUtilities.h"

// Set Logging Component
#undef RKLogComponent
#define RKLogComponent RKlcl_cRestKitCoreData

static id RKMutableSetValueForRelationship(NSRelationshipDescription *relationship)
{
    if (! [relationship isToMany]) return nil;
    return [relationship isOrdered] ? [NSMutableOrderedSet orderedSet] : [NSMutableSet set];
}

@interface RKRelationshipConnectionOperation ()
@property (nonatomic, strong, readwrite) NSManagedObject *managedObject;
@property (nonatomic, strong, readwrite) RKConnectionDescription *connection;
@property (nonatomic, strong, readwrite) id<RKManagedObjectCaching> managedObjectCache;
@property (nonatomic, strong, readwrite) NSError *error;
@property (nonatomic, strong, readwrite) id connectedValue;
@property (nonatomic, copy) void (^connectionBlock)(RKRelationshipConnectionOperation *operation, id connectedValue);

// Helpers
@property (weak, nonatomic, readonly) NSManagedObjectContext *managedObjectContext;

@end

@implementation RKRelationshipConnectionOperation

- (id)initWithManagedObject:(NSManagedObject *)managedObject
                           connection:(RKConnectionDescription *)connection
                   managedObjectCache:(id<RKManagedObjectCaching>)managedObjectCache;
{
    NSParameterAssert(managedObject);
    NSAssert([managedObject isKindOfClass:[NSManagedObject class]], @"Relationship connection requires an instance of NSManagedObject");
    NSParameterAssert(connection);
    NSParameterAssert(managedObjectCache);
    self = [self init];
    if (self) {
        self.managedObject = managedObject;
        self.connection = connection;
        self.managedObjectCache = managedObjectCache;
    }

    return self;
}

- (NSManagedObjectContext *)managedObjectContext
{
    return self.managedObject.managedObjectContext;
}

- (id)relationshipValueWithConnectionResult:(id)result
{
    // TODO: Replace with use of object mapping engine for type conversion

    // NOTE: This is a nasty hack to work around the fact that NSOrderedSet does not support key-value
    // collection operators. We try to detect and unpack a doubly wrapped collection
    if ([self.connection.relationship isToMany] && RKObjectIsCollectionOfCollections(result)) {
        id mutableSet = RKMutableSetValueForRelationship(self.connection.relationship);
        for (id<NSFastEnumeration> enumerable in result) {
            for (id object in enumerable) {
                [mutableSet addObject:object];
            }
        }

        return mutableSet;
    }

    if ([self.connection.relationship isToMany]) {
        if ([result isKindOfClass:[NSArray class]]) {
            if ([self.connection.relationship isOrdered]) {
                return [NSOrderedSet orderedSetWithArray:result];
            } else {
                return [NSSet setWithArray:result];
            }
        } else if ([result isKindOfClass:[NSSet class]]) {
            if ([self.connection.relationship isOrdered]) {
                return [NSOrderedSet orderedSetWithSet:result];
            } else {
                return result;
            }
        } else if ([result isKindOfClass:[NSOrderedSet class]]) {
            if ([self.connection.relationship isOrdered]) {
                return result;
            } else {
                return [(NSOrderedSet *)result set];
            }
        } else {
            if ([self.connection.relationship isOrdered]) {
                return [NSOrderedSet orderedSetWithObject:result];
            } else {
                return [NSSet setWithObject:result];
            }
        }
    }

    return result;
}

- (id)findConnected:(BOOL *)shouldConnectRelationship
{
    *shouldConnectRelationship = YES;
    if (self.connection.sourcePredicate && ![self.connection.sourcePredicate evaluateWithObject:self.managedObject]) return nil;
    id connectionResult = [self.connection findRelatedObjectFor:self.managedObject inManagedObjectCache:self.managedObjectCache];
    if (!connectionResult) {
        *shouldConnectRelationship = NO;
        return nil;
    }
    return [self relationshipValueWithConnectionResult:connectionResult];
}

- (void)main
{
    if (self.isCancelled) return;
    NSString *relationshipName = self.connection.relationship.name;
    RKLogTrace(@"Connecting relationship '%@' with mapping: %@", relationshipName, self.connection);
    [self.managedObjectContext performBlockAndWait:^{
        BOOL shouldConnect = YES;
        self.connectedValue = [self findConnected:&shouldConnect];
        if (shouldConnect) {
            [self.managedObject setValue:self.connectedValue forKeyPath:relationshipName];
            RKLogDebug(@"Connected relationship '%@' to object '%@'", relationshipName, self.connectedValue);
            if (self.connectionBlock) self.connectionBlock(self, self.connectedValue);
        }
    }];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@:%p %@ in %@ using %@>",
            [self class], self, self.connection, self.managedObjectContext, self.managedObjectCache];
}

@end
