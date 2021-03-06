/*
 Copyright 2015 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKContact.h"

#import "MXKEmail.h"
#import "MXKPhoneNumber.h"

NSString *const kMXKContactThumbnailUpdateNotification = @"kMXKContactThumbnailUpdateNotification";

NSString *const kMXKContactLocalContactPrefixId = @"Local_";
NSString *const kMXKContactMatrixContactPrefixId = @"Matrix_";

@interface MXKContact()
{
    UIImage* contactBookThumbnail;
    UIImage* matrixThumbnail;
    
    // The matrix id of the contact (used when the contact is not defined in the contacts book)
    MXKContactField *matrixIdField;
}
@end

@implementation MXKContact
@synthesize isMatrixContact;

+ (NSString*)contactID:(ABRecordRef)record
{
    return [NSString stringWithFormat:@"%@%d", kMXKContactLocalContactPrefixId, ABRecordGetRecordID(record)];
}

- (id)initLocalContactWithABRecord:(ABRecordRef)record
{
    self = [super init];
    
    if (self)
    {
        // compute a contact ID
        _contactID = [MXKContact contactID:record];
        
        // use the contact book display name
        _displayName = (__bridge NSString*) ABRecordCopyCompositeName(record);
        
        // avoid nil display name
        // the display name is used to sort contacts
        if (!_displayName)
        {
            _displayName = @"";
        }
        
        matrixIdField = nil;
        isMatrixContact = NO;
        
        // extract the phone numbers and their related label
        ABMultiValueRef multi = ABRecordCopyValue(record, kABPersonPhoneProperty);
        CFIndex        nCount = ABMultiValueGetCount(multi);
        NSMutableArray* pns = [[NSMutableArray alloc] initWithCapacity:nCount];
        
        for (int i = 0; i < nCount; i++)
        {
            CFTypeRef phoneRef = ABMultiValueCopyValueAtIndex(multi, i);
            NSString *phoneVal = (__bridge NSString*)phoneRef;
            
            // sanity check
            if (0 != [phoneVal length])
            {
                CFStringRef lblRef = ABMultiValueCopyLabelAtIndex(multi, i);
                CFStringRef localizedLblRef = nil;
                NSString *lbl =  @"";
                
                if (lblRef != nil)
                {
                    localizedLblRef = ABAddressBookCopyLocalizedLabel(lblRef);
                    if (localizedLblRef)
                    {
                        lbl = (__bridge NSString*)localizedLblRef;
                    }
                    else
                    {
                        lbl = (__bridge NSString*)lblRef;
                    }
                }
                else
                {
                    localizedLblRef = ABAddressBookCopyLocalizedLabel(kABOtherLabel);
                    if (localizedLblRef)
                    {
                        lbl = (__bridge NSString*)localizedLblRef;
                    }
                }
                
                [pns addObject:[[MXKPhoneNumber alloc] initWithTextNumber:phoneVal type:lbl contactID:_contactID matrixID:nil]];
                
                if (lblRef)
                {
                    CFRelease(lblRef);
                }
                if (localizedLblRef)
                {
                    CFRelease(localizedLblRef);
                }
            }
            
            // release meory
            if (phoneRef)
            {
                CFRelease(phoneRef);
            }
        }
        
        CFRelease(multi);
        _phoneNumbers = pns;
        
        // extract the emails
        multi = ABRecordCopyValue(record, kABPersonEmailProperty);
        nCount = ABMultiValueGetCount(multi);
        
        NSMutableArray *emails = [[NSMutableArray alloc] initWithCapacity:nCount];
        
        for (int i = 0; i < nCount; i++)
        {
            CFTypeRef emailValRef = ABMultiValueCopyValueAtIndex(multi, i);
            NSString *emailVal = (__bridge NSString*)emailValRef;
            
            // sanity check
            if ((nil != emailVal) && (0 != [emailVal length]))
            {
                CFStringRef lblRef = ABMultiValueCopyLabelAtIndex(multi, i);
                CFStringRef localizedLblRef = nil;
                NSString *lbl =  @"";
                
                if (lblRef != nil)
                {
                    localizedLblRef = ABAddressBookCopyLocalizedLabel(lblRef);
                    
                    if (localizedLblRef)
                    {
                        lbl = (__bridge NSString*)localizedLblRef;
                    }
                    else
                    {
                        lbl = (__bridge NSString*)lblRef;
                    }
                }
                else
                {
                    localizedLblRef = ABAddressBookCopyLocalizedLabel(kABOtherLabel);
                    if (localizedLblRef)
                    {
                        lbl = (__bridge NSString*)localizedLblRef;
                    }
                }
                
                [emails addObject: [[MXKEmail alloc] initWithEmailAddress:emailVal type:lbl contactID:_contactID matrixID:nil]];
                
                if (lblRef)
                {
                    CFRelease(lblRef);
                }
                
                if (localizedLblRef)
                {
                    CFRelease(localizedLblRef);
                }
            }
            
            if (emailValRef)
            {
                CFRelease(emailValRef);
            }
        }
        
        CFRelease(multi);
        
        _emailAddresses = emails;
        
        // thumbnail/picture
        // check whether the contact has a picture
        if (ABPersonHasImageData(record))
            
        {
            CFDataRef dataRef;
            
            dataRef = ABPersonCopyImageDataWithFormat(record, kABPersonImageFormatThumbnail);
            if (dataRef)
                
            {
                contactBookThumbnail = [UIImage imageWithData:(__bridge NSData*)dataRef];
                CFRelease(dataRef);
            }
        }
    }
    return self;
}

- (id)initMatrixContactWithDisplayName:(NSString*)aDisplayName andMatrixID:(NSString*)matrixID
{
    self = [super init];
    
    if (self)
    {
        _contactID = [NSString stringWithFormat:@"%@%@", kMXKContactMatrixContactPrefixId, [[NSUUID UUID] UUIDString]];
        
        // Sanity check
        if (matrixID.length)
        {
            // used when the contact is not defined in the contacts book
            matrixIdField = [[MXKContactField alloc] initWithContactID:_contactID matrixID:matrixID];
            isMatrixContact = YES;
        }
        
        // _displayName must not be nil
        // it is used to sort the contacts
        if (aDisplayName)
        {
            _displayName = aDisplayName;
        }
        else
        {
            _displayName = @"";
        }
    }
    
    return self;
}

#pragma mark -

- (NSString*)sortingDisplayName
{
    if (!_sortingDisplayName)
    {
        // Sanity check - display name should not be nil here
        if (self.displayName)
        {
            NSCharacterSet *specialCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"_!~`@#$%^&*-+();:={}[],.<>?\\/\"\'"];
            
            _sortingDisplayName = [self.displayName stringByTrimmingCharactersInSet:specialCharacterSet];
        }
        else
        {
            return @"";
        }
    }
    
    return _sortingDisplayName;
}

- (BOOL)hasPrefix:(NSString*)prefix
{
    prefix = [prefix lowercaseString];
    
    // Check first display name
    if (_displayName.length)
    {
        NSArray *components = [_displayName componentsSeparatedByString:@" "];
        for (NSString *component in components)
        {
            NSString *theComponent = [[component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
            if ([theComponent hasPrefix:prefix])
            {
                return YES;
            }
        }
    }
    
    // Check matrix identifiers
    NSArray *identifiers = self.matrixIdentifiers;
    NSString *idPrefix = [NSString stringWithFormat:@"@%@", prefix];
    for (NSString* mxId in identifiers)
    {
        if ([[mxId lowercaseString] hasPrefix:idPrefix])
        {
            return YES;
        }
    }
    
    // Check email
    for (MXKEmail* email in _emailAddresses)
    {
        if ([[email.emailAddress lowercaseString] hasPrefix:prefix])
        {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)matchedWithPatterns:(NSArray*)patterns
{
    BOOL matched = NO;
    
    if (patterns.count > 0)
    {
        matched = YES;
        
        // test first display name
        for (NSString* pattern in patterns)
        {
            if ([_displayName rangeOfString:pattern options:NSCaseInsensitiveSearch].location == NSNotFound)
            {
                matched = NO;
                break;
            }
        }
        
        NSArray *identifiers = self.matrixIdentifiers;
        if (!matched && identifiers.count > 0)
        {
            for (NSString* mxId in identifiers)
            {
                // Consider only the first part of the matrix id (ignore homeserver name)
                NSRange range = [mxId rangeOfString:@":"];
                if (range.location != NSNotFound)
                {
                    NSString *mxIdName = [mxId substringToIndex:range.location];
                    for (NSString* pattern in patterns)
                    {
                        if ([mxIdName rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound)
                        {
                            matched = YES;
                            break;
                        }
                    }
                    
                    if (matched)
                    {
                        break;
                    }
                }
            }
        }
        
        if (!matched && _phoneNumbers.count > 0)
        {
            for (MXKPhoneNumber* phonenumber in _phoneNumbers)
            {
                if ([phonenumber matchedWithPatterns:patterns])
                {
                    matched = YES;
                    break;
                }
            }
        }
        
        if (!matched && _emailAddresses.count > 0)
        {
            for (MXKEmail* email in _emailAddresses)
            {
                if ([email matchedWithPatterns:patterns])
                {
                    matched = YES;
                    break;
                }
            }
        }
    }
    else
    {
        // if there is no pattern to search, it should always matched
        matched = YES;
    }
    
    return matched;
}

- (void)internationalizePhonenumbers:(NSString*)countryCode
{
    for(MXKPhoneNumber* phonenumber in _phoneNumbers)
    {
        phonenumber.countryCode = countryCode;
    }
}

#pragma mark - getter/setter

- (NSArray*)matrixIdentifiers
{
    NSMutableArray* identifiers = [[NSMutableArray alloc] init];
    
    if (matrixIdField)
    {
        [identifiers addObject:matrixIdField.matrixID];
    }
    
    for(MXKEmail* email in _emailAddresses)
    {
        if (email.matrixID && ([identifiers indexOfObject:email.matrixID] == NSNotFound))
        {
            [identifiers addObject:email.matrixID];
        }
    }
    
    for(MXKPhoneNumber* pn in _phoneNumbers)
    {
        if (pn.matrixID && ([identifiers indexOfObject:pn.matrixID] == NSNotFound))
        {
            [identifiers addObject:pn.matrixID];
        }
    }
    
    return identifiers;
}

- (void)setDisplayName:(NSString *)displayName
{
    // a display name must not be emptied
    // it is used to sort the contacts
    if (displayName.length == 0)
    {
        _displayName = _contactID;
    }
    else
    {
        _displayName = displayName;
    }
}

- (UIImage*)thumbnailWithPreferedSize:(CGSize)size
{
    // already found a matrix thumbnail
    if (matrixThumbnail)
    {
        return matrixThumbnail;
    }
    else
    {
        MXKContactField* firstField = matrixIdField;
        if (firstField)
        {
            if (firstField.avatarImage)
            {
                matrixThumbnail = firstField.avatarImage;
                return matrixThumbnail;
            }
        }
        
        // try to replace the thumbnail by the matrix one
        if (_emailAddresses.count > 0)
        {
            // list the linked email
            // search if one email field has a dedicated thumbnail
            for(MXKEmail* email in _emailAddresses)
            {
                if (email.avatarImage)
                {
                    matrixThumbnail = email.avatarImage;
                    return matrixThumbnail;
                }
                else if (!firstField && email.matrixID)
                {
                    firstField = email;
                }
            }
        }
        
        // if no thumbnail has been found
        // try to load the first field one
        if (firstField)
        {
            // should be retrieved by the cell info
            [firstField loadAvatarWithSize:size];
        }
        
        return contactBookThumbnail;
    }
}

- (UIImage*)thumbnail
{
    return [self thumbnailWithPreferedSize:CGSizeMake(256, 256)];
}

#pragma mark NSCoding

- (id)initWithCoder:(NSCoder *)coder
{
    _contactID = [coder decodeObjectForKey:@"contactID"];
    _displayName = [coder decodeObjectForKey:@"displayName"];
    
    matrixIdField = [coder decodeObjectForKey:@"matrixIdField"];
    
    _phoneNumbers = [coder decodeObjectForKey:@"phoneNumbers"];
    _emailAddresses = [coder decodeObjectForKey:@"emailAddresses"];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    
    [coder encodeObject:_contactID forKey:@"contactID"];
    [coder encodeObject:_displayName forKey:@"displayName"];
    
    if (matrixIdField)
    {
        [coder encodeObject:matrixIdField forKey:@"matrixIdField"];
    }
    
    if (_phoneNumbers.count)
    {
        [coder encodeObject:_phoneNumbers forKey:@"phoneNumbers"];
    }
    
    if (_emailAddresses.count)
    {
        [coder encodeObject:_emailAddresses forKey:@"emailAddresses"];
    }
}

@end
