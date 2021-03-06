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

#define MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH 192

#define MXKROOMBUBBLECELLDATA_DEFAULT_MAX_TEXTVIEW_WIDTH 200

#import "MXKRoomBubbleCellData.h"

#import "MXKTools.h"
#import "MXKMediaManager.h"

@implementation MXKRoomBubbleCellData
@synthesize senderId, roomId, senderDisplayName, senderAvatarUrl, senderAvatarPlaceholder, isPaginationFirstBubble, shouldHideSenderInformation, date, isIncoming, isAttachmentWithThumbnail, isAttachmentWithIcon, attachment;
@synthesize textMessage, attributedTextMessage;
@synthesize shouldHideSenderName, isTyping, showBubbleDateTime, showBubbleReceipts, useCustomDateTimeLabel, useCustomReceipts, useCustomUnsentButton;

#pragma mark - MXKRoomBubbleCellDataStoring

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)roomDataSource2
{
    self = [self init];
    if (self)
    {
        roomDataSource = roomDataSource2;
        
        // Create the bubble component based on matrix event
        MXKRoomBubbleComponent *firstComponent = [[MXKRoomBubbleComponent alloc] initWithEvent:event andRoomState:roomState andEventFormatter:roomDataSource.eventFormatter];
        if (firstComponent)
        {
            bubbleComponents = [NSMutableArray array];
            [bubbleComponents addObject:firstComponent];
            
            senderId = event.sender;
            roomId = roomDataSource.roomId;
            senderDisplayName = [roomDataSource.eventFormatter senderDisplayNameForEvent:event withRoomState:roomState];
            senderAvatarUrl = [roomDataSource.eventFormatter senderAvatarUrlForEvent:event withRoomState:roomState];
            senderAvatarPlaceholder = nil;
            isIncoming = ([event.sender isEqualToString:roomDataSource.mxSession.myUser.userId] == NO);
            
            // Check attachment if any
            if ([roomDataSource.eventFormatter isSupportedAttachment:event])
            {
                // Note: event.eventType is equal here to MXEventTypeRoomMessage
                attachment = [[MXKAttachment alloc] initWithEvent:event andMatrixSession:roomDataSource.mxSession];
                if (attachment && attachment.type == MXKAttachmentTypeImage && attachment.thumbnailURL == nil)
                {
                    // Suppose contentURL is a matrix content uri, we use SDK to get the well adapted thumbnail from server
                    attachment.thumbnailURL = [roomDataSource.mxSession.matrixRestClient urlOfContentThumbnail:attachment.contentURL
                                                                                                  toFitViewSize:self.contentSize
                                                                                                     withMethod:MXThumbnailingMethodScale];
                    
                    // Check the current thumbnail orientation. Rotate the current content size (if need)
                    if (attachment.thumbnailOrientation == UIImageOrientationLeft || attachment.thumbnailOrientation == UIImageOrientationRight)
                    {
                        _contentSize = CGSizeMake(_contentSize.height, _contentSize.width);
                    }
                }
            }
            
            // Report the attributed string (This will initialize _contentSize attribute)
            self.attributedTextMessage = firstComponent.attributedTextMessage;
            
            // Initialize rendering attributes
            _maxTextViewWidth = MXKROOMBUBBLECELLDATA_DEFAULT_MAX_TEXTVIEW_WIDTH;
        }
        else
        {
            // Ignore this event
            self = nil;
        }
    }
    return self;
}

- (void)dealloc
{
    roomDataSource = nil;
    bubbleComponents = nil;
}

- (NSUInteger)updateEvent:(NSString *)eventId withEvent:(MXEvent *)event
{
    NSUInteger count = 0;

    @synchronized(bubbleComponents)
    {
        // Retrieve the component storing the event and update it
        for (NSUInteger index = 0; index < bubbleComponents.count; index++)
        {
            MXKRoomBubbleComponent *roomBubbleComponent = [bubbleComponents objectAtIndex:index];
            if ([roomBubbleComponent.event.eventId isEqualToString:eventId])
            {
                [roomBubbleComponent updateWithEvent:event andRoomState:roomDataSource.room.state];
                if (!roomBubbleComponent.textMessage.length)
                {
                    [bubbleComponents removeObjectAtIndex:index];
                }
                // flush the current attributed string to force refresh
                self.attributedTextMessage = nil;
                
                // Handle here attachment update.
                // The case of update of attachment event happens when an echo is replaced by its true event
                // received back by the events stream.
                if (attachment)
                {
                    // Check the current content url, to update it with the actual one
                    if (![attachment.event.eventId isEqualToString:event.eventId] || ![attachment.contentURL isEqualToString:event.content[@"url"]])
                    {
                        MXKAttachment *updatedAttachment = [[MXKAttachment alloc] initWithEvent:event andMatrixSession:roomDataSource.mxSession];
                        
                        // Sanity check on attachment type
                        if (updatedAttachment && attachment.type == updatedAttachment.type)
                        {
                            // Store the echo image as preview to prevent the cell from flashing
                            updatedAttachment.previewURL = attachment.actualURL;
                            
                            // Update the current attachmnet description
                            attachment = updatedAttachment;
                            
                            if (attachment.type == MXKAttachmentTypeImage && attachment.thumbnailURL == nil)
                            {
                                // Reset content size
                                _contentSize = CGSizeZero;
                                
                                // Suppose contentURL is a matrix content uri, we use SDK to get the well adapted thumbnail from server
                                attachment.thumbnailURL = [roomDataSource.mxSession.matrixRestClient urlOfContentThumbnail:attachment.contentURL
                                                                                                              toFitViewSize:self.contentSize
                                                                                                                 withMethod:MXThumbnailingMethodScale];
                                
                                // Check the current thumbnail orientation. Rotate the current content size (if need)
                                if (attachment.thumbnailOrientation == UIImageOrientationLeft || attachment.thumbnailOrientation == UIImageOrientationRight)
                                {
                                    _contentSize = CGSizeMake(_contentSize.height, _contentSize.width);
                                }
                            }
                        }
                        else
                        {
                            NSLog(@"[MXKRoomBubbleCellData] updateEvent: Warning: Does not support change of attachment type");
                        }
                    }
                }
                
                break;
            }
        }
        
        count = bubbleComponents.count;
    }
    
    return count;
}

- (NSUInteger)removeEvent:(NSString *)eventId
{
    NSUInteger count = 0;
    
    @synchronized(bubbleComponents)
    {
        for (MXKRoomBubbleComponent *roomBubbleComponent in bubbleComponents)
        {
            if ([roomBubbleComponent.event.eventId isEqualToString:eventId])
            {
                [bubbleComponents removeObject:roomBubbleComponent];
                
                // flush the current attributed string to force refresh
                self.attributedTextMessage = nil;
                
                break;
            }
        }
        
        count = bubbleComponents.count;
    }

    return count;
}

- (BOOL)hasSameSenderAsBubbleCellData:(id<MXKRoomBubbleCellDataStoring>)bubbleCellData
{
    // Sanity check: accept only object of MXKRoomBubbleCellData classes or sub-classes
    NSParameterAssert([bubbleCellData isKindOfClass:[MXKRoomBubbleCellData class]]);
    
    // NOTE: Same sender means here same id, same display name and same avatar
    
    // Check first user id
    if ([senderId isEqualToString:bubbleCellData.senderId] == NO)
    {
        return NO;
    }
    // Check sender name
    if ((senderDisplayName.length || bubbleCellData.senderDisplayName.length) && ([senderDisplayName isEqualToString:bubbleCellData.senderDisplayName] == NO))
    {
        return NO;
    }
    // Check avatar url
    if ((senderAvatarUrl.length || bubbleCellData.senderAvatarUrl.length) && ([senderAvatarUrl isEqualToString:bubbleCellData.senderAvatarUrl] == NO))
    {
        return NO;
    }
    
    return YES;
}

- (MXKRoomBubbleComponent*) getFirstBubbleComponent
{
    MXKRoomBubbleComponent* first = nil;
    
    @synchronized(bubbleComponents)
    {
        if (bubbleComponents.count)
        {
            first = [bubbleComponents firstObject];
        }
    }
    
    return first;
}

- (NSAttributedString*)attributedTextMessageWithHighlightedEvent:(NSString*)eventId tintColor:(UIColor*)tintColor
{
    NSAttributedString *customAttributedTextMsg;
    
    // By default only one component is supported, consider here the first component
    MXKRoomBubbleComponent *firstComponent = [self getFirstBubbleComponent];
    
    if (firstComponent)
    {
        customAttributedTextMsg = firstComponent.attributedTextMessage;
        
        // Sanity check
        if ([firstComponent.event.eventId isEqualToString:eventId])
        {
            NSMutableAttributedString *customComponentString = [[NSMutableAttributedString alloc] initWithAttributedString:customAttributedTextMsg];
            UIColor *color = tintColor ? tintColor : [UIColor lightGrayColor];
            [customComponentString addAttribute:NSBackgroundColorAttributeName value:color range:NSMakeRange(0, customComponentString.length)];
            customAttributedTextMsg = customComponentString;
        }
    }

    return customAttributedTextMsg;
}

#pragma mark -

- (void)prepareBubbleComponentsPosition
{
    // Consider here only the first component if any
    MXKRoomBubbleComponent *firstComponent = [self getFirstBubbleComponent];
    
    if (firstComponent)
    {
        CGFloat positionY = (attachment == nil || attachment.type == MXKAttachmentTypeFile) ? MXKROOMBUBBLECELLDATA_TEXTVIEW_DEFAULT_VERTICAL_INSET : 0;
        firstComponent.position = CGPointMake(0, positionY);
    }
}

#pragma mark - Text measuring

// Return the raw height of the provided text by removing any margin
- (CGFloat)rawTextHeight: (NSAttributedString*)attributedText
{
    __block CGSize textSize;
    if ([NSThread currentThread] != [NSThread mainThread])
    {
        dispatch_sync(dispatch_get_main_queue(), ^{
            textSize = [self textContentSize:attributedText removeVerticalInset:YES];
        });
    }
    else
    {
        textSize = [self textContentSize:attributedText removeVerticalInset:YES];
    }
    
    return textSize.height;
}

- (CGSize)textContentSize:(NSAttributedString*)attributedText removeVerticalInset:(BOOL)removeVerticalInset
{
    static UITextView* measurementTextView = nil;
    static UITextView* measurementTextViewWithoutInset = nil;
    
    if (attributedText.length)
    {
        if (!measurementTextView)
        {
            measurementTextView = [[UITextView alloc] init];
            
            measurementTextViewWithoutInset = [[UITextView alloc] init];
            // Remove the container inset: this operation impacts only the vertical margin.
            // Note: consider textContainer.lineFragmentPadding to remove horizontal margin
            measurementTextViewWithoutInset.textContainerInset = UIEdgeInsetsZero;
        }
        
        // Select the right text view for measurement
        UITextView *selectedTextView = (removeVerticalInset ? measurementTextViewWithoutInset : measurementTextView);
        
        selectedTextView.frame = CGRectMake(0, 0, _maxTextViewWidth, MAXFLOAT);
        selectedTextView.attributedText = attributedText;
            
        CGSize size = [selectedTextView sizeThatFits:measurementTextView.frame.size];

        // Manage the case where a string attribute has a single paragraph with a left indent
        // In this case, [UITextViex sizeThatFits] ignores the indent and return the width
        // of the text only.
        // So, add this indent afterwards
        NSRange textRange = NSMakeRange(0, attributedText.length);
        NSRange longestEffectiveRange;
        NSParagraphStyle *paragraphStyle = [attributedText attribute:NSParagraphStyleAttributeName atIndex:0 longestEffectiveRange:&longestEffectiveRange inRange:textRange];

        if (NSEqualRanges(textRange, longestEffectiveRange))
        {
            size.width = size.width + paragraphStyle.headIndent;
        }

        return size;
    }
    
    return CGSizeZero;
}

#pragma mark - Properties

- (MXSession*)mxSession
{
    return roomDataSource.mxSession;
}

- (NSArray*)bubbleComponents
{
    NSArray* copy;
    
    @synchronized(bubbleComponents)
    {
        copy = [bubbleComponents copy];
    }
    
    return copy;
}

- (NSString*)textMessage
{
    return self.attributedTextMessage.string;
}

- (void)setAttributedTextMessage:(NSAttributedString *)inAttributedTextMessage
{
    attributedTextMessage = inAttributedTextMessage;
    
    // Reset content size
    _contentSize = CGSizeZero;
}

- (NSAttributedString*)attributedTextMessage
{
    if (!attributedTextMessage.length)
    {
        // By default only one component is supported, consider here the first component
        MXKRoomBubbleComponent *firstComponent = [self getFirstBubbleComponent];
        
        if (firstComponent)
        {
            attributedTextMessage = firstComponent.attributedTextMessage;
        }
    }

    return attributedTextMessage;
}

- (BOOL)shouldHideSenderName
{
    BOOL res = NO;

    // Consider the first component
    MXKRoomBubbleComponent *firstComponent = [self getFirstBubbleComponent];
    
    if (firstComponent)
    {
        res = (firstComponent.event.isEmote || (firstComponent.event.isState && [firstComponent.textMessage hasPrefix:senderDisplayName]));
    }
    
    return res;
}

- (NSArray*)events
{
    NSMutableArray* eventsArray;
    
    @synchronized(bubbleComponents)
    {
        eventsArray = [NSMutableArray arrayWithCapacity:bubbleComponents.count];
        for (MXKRoomBubbleComponent *roomBubbleComponent in bubbleComponents)
        {
            if (roomBubbleComponent.event)
            {
                [eventsArray addObject:roomBubbleComponent.event];
            }
        }
    }
    return eventsArray;
}

- (NSDate*)date
{
    MXKRoomBubbleComponent *firstComponent = [self getFirstBubbleComponent];
    
    if (firstComponent)
    {
        return firstComponent.date;
    }
    
    return nil;
}

- (BOOL)isAttachmentWithThumbnail
{
    return (attachment && (attachment.type == MXKAttachmentTypeImage || attachment.type == MXKAttachmentTypeVideo));
}

- (BOOL)isAttachmentWithIcon
{
    // Not supported yet (TODO for audio, file).
    return NO;
}

- (void)setMaxTextViewWidth:(CGFloat)inMaxTextViewWidth
{
    // Check change
    if (inMaxTextViewWidth != _maxTextViewWidth)
    {
        _maxTextViewWidth = inMaxTextViewWidth;
        // Reset content size
        _contentSize = CGSizeZero;
    }
}

- (CGSize)contentSize
{
    if (CGSizeEqualToSize(_contentSize, CGSizeZero))
    {
        if (attachment == nil)
        {
            // Here the bubble is a text message
            if ([NSThread currentThread] != [NSThread mainThread])
            {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    _contentSize = [self textContentSize:self.attributedTextMessage removeVerticalInset:NO];
                });
            }
            else
            {
                _contentSize = [self textContentSize:self.attributedTextMessage removeVerticalInset:NO];
            }
        }
        else if (self.isAttachmentWithThumbnail)
        {
            CGFloat width, height;
            
            // Set default content size
            width = height = MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH;
            
            if (attachment.thumbnailInfo || attachment.contentInfo)
            {
                if (attachment.thumbnailInfo && attachment.thumbnailInfo[@"w"] && attachment.thumbnailInfo[@"h"])
                {
                    width = [attachment.thumbnailInfo[@"w"] integerValue];
                    height = [attachment.thumbnailInfo[@"h"] integerValue];
                }
                else if (attachment.contentInfo[@"w"] && attachment.contentInfo[@"h"])
                {
                    width = [attachment.contentInfo[@"w"] integerValue];
                    height = [attachment.contentInfo[@"h"] integerValue];
                }
                
                if (width > MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH || height > MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH)
                {
                    if (width > height)
                    {
                        height = (height * MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH) / width;
                        height = floorf(height / 2) * 2;
                        width = MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH;
                    }
                    else
                    {
                        width = (width * MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH) / height;
                        width = floorf(width / 2) * 2;
                        height = MXKROOMBUBBLECELLDATA_MAX_ATTACHMENTVIEW_WIDTH;
                    }
                }
            }
            
            // Check here thumbnail orientation
            if (attachment.thumbnailOrientation == UIImageOrientationLeft || attachment.thumbnailOrientation == UIImageOrientationRight)
            {
                _contentSize = CGSizeMake(height, width);
            }
            else
            {
                _contentSize = CGSizeMake(width, height);
            }
        }
        else if (attachment.type == MXKAttachmentTypeFile)
        {
            // Presently we displayed only the file name for attached file (no icon yet)
            // Return suitable content size of a text view to display the file name (available in text message). 
            if ([NSThread currentThread] != [NSThread mainThread])
            {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    _contentSize = [self textContentSize:self.attributedTextMessage removeVerticalInset:NO];
                });
            }
            else
            {
                _contentSize = [self textContentSize:self.attributedTextMessage removeVerticalInset:NO];
            }
        }
        else
        {
            _contentSize = CGSizeMake(40, 40);
        }
    }
    return _contentSize;
}

- (MXKEventFormatter *)eventFormatter
{
    MXKRoomBubbleComponent *firstComponent = [bubbleComponents firstObject];
    
    // Retrieve event formatter from the first component
    if (firstComponent)
    {
        return firstComponent.eventFormatter;
    }
    
    return nil;
}

@end
