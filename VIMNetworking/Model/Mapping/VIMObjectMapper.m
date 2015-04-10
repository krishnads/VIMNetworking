//
//  VIMObjectMapper.m
//  VIMNetworking
//
//  Created by Kashif Mohammad on 3/25/13.
//  Copyright (c) 2013 Vimeo. All rights reserved.
//

#import "VIMObjectMapper.h"
#import "VIMMappable.h"

@interface VIMObjectMapper ()
{
    NSMutableDictionary *_mappingDict;
}

@end

@implementation VIMObjectMapper

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        _mappingDict = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (void)addMappingClass:(Class)mappingClass forKeypath:(NSString *)keypath
{
    [_mappingDict setObject:mappingClass forKey:keypath];
}

- (NSString *)underscoreCaseToCamelCase:(NSString *)key
{
	if([key rangeOfString:@"_"].location == NSNotFound)
		return key;
    
    // Remove underscore from start and end
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]];
    
    NSArray *components = [key componentsSeparatedByString:@"_"];
    if(components.count == 0)
        return key;
    
	NSMutableString *output = [NSMutableString stringWithString:components[0]];
    for(int i = 1;i < components.count;i++)
        [output appendString:[[components objectAtIndex:i] capitalizedString]];
	
	return output;
}

- (id)_createObjectFromDictionary:(NSDictionary *)jsonDict mappingClass:(Class)mappingClass
{
	//NSLog(@"_createObjectFromDictionary: mappingClass = %@, jsonDict = %@", mappingClass, jsonDict);
	
    __block NSObject<VIMMappable> *newObject = [[mappingClass alloc] init];

	NSDictionary *keyValueDict = nil;
	if([newObject respondsToSelector:@selector(getObjectMapping)])
		keyValueDict = [newObject getObjectMapping];
    
    [jsonDict enumerateKeysAndObjectsUsingBlock:^(id jsonKey, id jsonValue, BOOL *stop) {

		if([newObject isKindOfClass:[NSDictionary class]])
		{
			[newObject setValue:jsonValue forKey:jsonKey];
			return;
		}
		
		id objectKey = nil;
		if(keyValueDict)
			objectKey = [keyValueDict objectForKey:jsonKey];
        
		if(objectKey == nil)
			objectKey = [self underscoreCaseToCamelCase:jsonKey];

		if([jsonValue isKindOfClass:[NSDictionary class]])
		{
			if([newObject respondsToSelector:@selector(getClassForObjectKey:)])
			{
                __block BOOL keyFound = NO;
                
				Class childClass = [newObject getClassForObjectKey:jsonKey];
				if(childClass)
				{
					id childObject = [self _createObjectFromDictionary:jsonValue mappingClass:childClass];
					[newObject setValue:childObject forKey:objectKey];
                    
                    keyFound = YES;
				}
                else if([newObject respondsToSelector:@selector(getClassForCollectionKey:)])
                {
                    NSDictionary *childDict = jsonValue;
                    [childDict enumerateKeysAndObjectsUsingBlock:^(id childKey, id childValue, BOOL *stop) {
                        Class childCollectionClass = [newObject getClassForCollectionKey:[jsonKey stringByAppendingFormat:@".%@", childKey]];
                        if(childCollectionClass)
                        {
                            id childObject = [self _createObjectsFromJSON:childValue keypath:@"" mappingClass:childCollectionClass];
                            [newObject setValue:childObject forKey:objectKey];
                            
                            keyFound = YES;
                            *stop = YES;
                        }
                    }];
                }
                
                if(keyFound == NO)
                {
                    [newObject setValue:jsonValue forKey:objectKey];
                }
			}
		}
		else if([jsonValue isKindOfClass:[NSArray class]])
		{
            Class arrayClass = nil;
			if([newObject respondsToSelector:@selector(getClassForCollectionKey:)])
				arrayClass = [newObject getClassForCollectionKey:jsonKey];

            if(arrayClass)
            {
                id childObject = [self _createObjectsFromJSON:jsonValue keypath:@"" mappingClass:arrayClass];
                [newObject setValue:childObject forKey:objectKey];
            }
            else
            {
                //NSLog(@"_createObjectFromDictionary: No class specified for collection key: '%@'", jsonKey);

                // Set default collection class
                arrayClass = [NSMutableDictionary class];
                
                id childObject = [self _createObjectsFromJSON:jsonValue keypath:jsonKey mappingClass:arrayClass];
                [newObject setValue:childObject forKey:objectKey];
            }
		}
		else
		{
            if([jsonValue isKindOfClass:[NSNull class]] == NO)
                [newObject setValue:jsonValue forKey:objectKey];
		}
    }];
    
    if([newObject respondsToSelector:@selector(didFinishMapping)])
       [newObject didFinishMapping];
    
    return newObject;
}

- (id)_createObjectsFromJSON:(id)JSON keypath:(NSString *)keypath mappingClass:(Class)jsonClass
{
	//NSLog(@"_createObjectsFromJSON: keypath = %@, mappingClass = %@, JSON=%@", keypath, mappingClass, JSON);
	
    __block id result = nil;
    
    if([JSON isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *jsonDict = (NSDictionary *)JSON;

        __block BOOL objectParsed = NO;
        
        if(jsonClass == nil)
        {
			// Found dictionary at the top level of JSON. Try to find appropriate mapping for each key and map recursively
			
            result = [NSMutableDictionary dictionary];
            
            [_mappingDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {

				NSString *mappingDictKeypath = key;
				Class mappingDictClass = obj;

				if(mappingDictKeypath.length > 0)
				{
					NSArray *mappingKeypathComponents = [mappingDictKeypath componentsSeparatedByString:@"."];
					if(mappingKeypathComponents.count > 0)
					{
						NSString *jsonDictKey = [mappingKeypathComponents objectAtIndex:0];
						id jsonSubObject = [jsonDict objectForKey:jsonDictKey];
						if(jsonSubObject)
						{
							//NSLog(@"Found object for key in keypath: %@", jsonDictKey);
							NSString *subKeyPath = [[mappingKeypathComponents subarrayWithRange:NSMakeRange(1, mappingKeypathComponents.count-1)] componentsJoinedByString:@"."];
                            
							id parsedObject = [self _createObjectsFromJSON:jsonSubObject keypath:subKeyPath mappingClass:mappingDictClass];
							[result setObject:parsedObject forKey:jsonDictKey];

                            if(parsedObject)
                                objectParsed = YES;
						}
					}
				}
				else
				{
					result = [self _createObjectFromDictionary:jsonDict mappingClass:mappingDictClass];
                    
                    if(result)
                        objectParsed = YES;
                    
					*stop = YES;
				}
            }];
        }
        else
        {
            if(keypath.length > 0)
            {
				// Try to find the key that follows in our keypath
				
                result = [NSMutableDictionary dictionary];
                
                NSArray *mappingKeypathComponents = [keypath componentsSeparatedByString:@"."];
                if(mappingKeypathComponents.count > 0)
                {
                    NSString *jsonDictKey = [mappingKeypathComponents objectAtIndex:0];
                    id jsonSubObject = [jsonDict objectForKey:jsonDictKey];
                    if(jsonSubObject)
                    {
                        NSString *subKeyPath = [[mappingKeypathComponents subarrayWithRange:NSMakeRange(1, mappingKeypathComponents.count-1)] componentsJoinedByString:@"."];
                        
                        id parsedObject = [self _createObjectsFromJSON:jsonSubObject keypath:subKeyPath mappingClass:jsonClass];
                        [result setObject:parsedObject forKey:jsonDictKey];

                        if(parsedObject)
                            objectParsed = YES;
                    }
                }
            }
            else
            {
				// Found our object, map it from the dictionary
				
                result = [self _createObjectFromDictionary:jsonDict mappingClass:jsonClass];
                
                if(result)
                    objectParsed = YES;
            }
        }
        
        if(objectParsed == NO)
            result = [NSDictionary dictionaryWithDictionary:jsonDict];
    }
    else
    {
        if([JSON isKindOfClass:[NSArray class]])
        {
            NSArray *jsonArray = (NSArray *)JSON;

			if(jsonClass == nil)
			{
				// Found array at the top level of JSON. Just call recursively to map each array item

				NSMutableArray *resultArray = [NSMutableArray array];
				
				for(id jsonArrayItem in jsonArray)
					[resultArray addObject:[self _createObjectsFromJSON:jsonArrayItem keypath:keypath mappingClass:nil]];

				//result = @{@"" : resultArray};
				result = resultArray;
			}
			else
			{
				// Iterate through array items and try to map objects
				
				NSMutableArray *resultArray = [NSMutableArray array];
				
				for(id jsonArrayItem in jsonArray)
					[resultArray addObject:[self _createObjectsFromJSON:jsonArrayItem keypath:keypath mappingClass:jsonClass]];
				
				result = resultArray;
			}
        }
        else if([JSON isKindOfClass:[NSString class]])
        {
            result = JSON;
        }
        else
        {
			NSLog(@"_createObjectsFromJSON: Encountered an unknown object type '%@' in JSON", [JSON class]);
        }
    }
    
    return result;
}

- (id)applyMappingToJSON:(id)JSON
{
    return [self _createObjectsFromJSON:JSON keypath:@"" mappingClass:nil];
}

@end
