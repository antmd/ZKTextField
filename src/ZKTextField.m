//
// ZKTextField.m
// ZKTextField
//
// Created by Alex Zielenski on 4/11/12.
// Copyright (c) 2012 Alex Zielenski. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


// This is used for secure text fields for generating bullets rather than text for display.

#pragma mark - ZKSecureGlyphGenerator

@interface NSObject(TDBindings)
-(void) propagateValue:(id)value forBinding:(NSString*)binding;
@end
@implementation NSObject(TDBindings)

-(void) propagateValue:(id)value forBinding:(NSString*)binding;
{
	NSParameterAssert(binding != nil);
    
	//WARNING: bindingInfo contains NSNull, so it must be accounted for
	NSDictionary* bindingInfo = [self infoForBinding:binding];
	if(!bindingInfo)
		return; //there is no binding
    
	//apply the value transformer, if one has been set
	NSDictionary* bindingOptions = [bindingInfo objectForKey:NSOptionsKey];
	if(bindingOptions){
		NSValueTransformer* transformer = [bindingOptions valueForKey:NSValueTransformerBindingOption];
		if(!transformer || (id)transformer == [NSNull null]){
			NSString* transformerName = [bindingOptions valueForKey:NSValueTransformerNameBindingOption];
			if(transformerName && (id)transformerName != [NSNull null]){
				transformer = [NSValueTransformer valueTransformerForName:transformerName];
			}
		}
        
		if(transformer && (id)transformer != [NSNull null]){
			if([[transformer class] allowsReverseTransformation]){
				value = [transformer reverseTransformedValue:value];
			} else {
				NSLog(@"WARNING: binding \"%@\" has value transformer, but it doesn't allow reverse transformations in %s", binding, __PRETTY_FUNCTION__);
			}
		}
	}
    
	id boundObject = [bindingInfo objectForKey:NSObservedObjectKey];
	if(!boundObject || boundObject == [NSNull null]){
		NSLog(@"ERROR: NSObservedObjectKey was nil for binding \"%@\" in %s", binding, __PRETTY_FUNCTION__);
		return;
	}
    
	NSString* boundKeyPath = [bindingInfo objectForKey:NSObservedKeyPathKey];
	if(!boundKeyPath || (id)boundKeyPath == [NSNull null]){
		NSLog(@"ERROR: NSObservedKeyPathKey was nil for binding \"%@\" in %s", binding, __PRETTY_FUNCTION__);
		return;
	}
    
	[boundObject setValue:value forKeyPath:boundKeyPath];
}

@end

@interface ZKSecureGlyphGenerator : NSGlyphGenerator
@end

@implementation ZKSecureGlyphGenerator

- (void)generateGlyphsForGlyphStorage:(id < NSGlyphStorage> )glyphStorage
			desiredNumberOfCharacters:(NSUInteger)nChars
						   glyphIndex:(NSUInteger *)glyphIndex
					   characterIndex:(NSUInteger *)charIndex {

	NSFont *font = [glyphStorage.attributedString attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
	NSGlyph newGlyphs[1] = {[font glyphWithName:@"bullet"]};
	[glyphStorage insertGlyphs:newGlyphs length:1 forStartingGlyphAtIndex:*glyphIndex characterIndex:*charIndex];
}

@end

#import "ZKTextField.h"
#import <ApplicationServices/ApplicationServices.h>

#pragma mark - Private Class Extension


@interface ZKTextField () <NSTextViewDelegate, NSTextDelegate>
@property (nonatomic, strong) NSBezierPath *_currentClippingPath;
@property (nonatomic, strong) NSTextView   *_currentFieldEditor;
@property (nonatomic, strong) NSClipView   *_currentClipView;
@property (nonatomic, assign) CGFloat       _offset;
@property (nonatomic, assign) CGFloat       _lineHeight;
@property (nonatomic, strong) NSAttributedString *_bullets;

- (void)_configureFieldEditor;
- (void)_instantiate;
@end

static NSFont* DefaultFont = nil;
static const CGFloat MinimumFontSize = 6.0;
static const CGFloat MaximumFontSize = 48.0;

/*
 *
 *
 *================================================================================================*/
#pragma mark - Main Implementation
/*==================================================================================================
 */
#pragma mark - ZKTextField
#pragma mark -

@implementation ZKTextField {
    BOOL _isAttributedString ; // Whether an attributed string has been set by the user
    NSMutableAttributedString* _notEditingAttributedString;
    NSMutableDictionary* _notEditingTotalStringAttributes;
}

#pragma mark - Private Properties

@synthesize _currentClippingPath;
@synthesize _currentFieldEditor;
@synthesize _currentClipView;
@synthesize _lineHeight;
@synthesize _offset;
@synthesize _bullets;

#pragma mark - Public Properties

@dynamic string;
@dynamic placeholderString;
@synthesize attributedString            = _attributedString;
@synthesize attributedPlaceholderString = _attributedPlaceholderString;
@synthesize notEditingBackgroundColor             = _notEditingBackgroundColor;
@synthesize drawsBackground             = _drawsBackground;
@synthesize drawsBorder                 = _drawsBorder;
@synthesize hasHoverCursor              = _hasHoverCursor;
@synthesize shouldClipContent           = _shouldClipContent;
@synthesize secure                      = _secure;
@synthesize shouldShowFocus             = _shouldShowFocus;
@synthesize editable                    = _editable;
@synthesize selectable                  = _selectable;
@synthesize target                      = _target;
@synthesize action                      = _action;
@synthesize continuous                  = _continuous;
@synthesize stringAttributes            = _stringAttributes;
@synthesize placeholderStringAttributes = _placeholderStringAttributes;
@synthesize selectedStringAttributes    = _selectedStringAttributes;

#pragma mark - Lifecycle

+(void)initialize
{
    if (self == ZKTextField.class) {
        DefaultFont = [ NSFont systemFontOfSize:13.0 ];
    }
}
- (id)init 
{
	if ((self = [super init])) {
		[self _instantiate];
	}
	return self;
}

- (id)initWithFrame:(NSRect)frame
{
	if (([super initWithFrame:frame])) {		
		[self _instantiate];
		self.frame             = frame; // Recalculate frame
	}

	return self;
}

- (id)initWithCoder:(NSCoder *)dec
{
	if ((self = [super initWithCoder:dec])) {
		self.attributedString            = [dec decodeObjectForKey:@"zkattributedstring"];
		self.notEditingBackgroundColor             = [dec decodeObjectForKey:@"zkDeselectedBackgroundcolor"];
		self.editingBackgroundColor             = [dec decodeObjectForKey:@"zkSelectedBackgroundcolor"];
		self.notEditingStringAttributes             = [dec decodeObjectForKey:@"zkDeselectedForegroundcolor"];
		self.editingStringAttributes             = [dec decodeObjectForKey:@"zkSelectedForegroundcolor"];
		self.secure                      = [dec decodeBoolForKey:@"zksecure"];
		self.editable                    = [dec decodeBoolForKey:@"zkeditable"];
		self.selectable                  = [dec decodeBoolForKey:@"zkselectable"];
		self.shouldShowFocus             = [dec decodeBoolForKey:@"zkshouldshowfocus"];
		self.shouldClipContent           = [dec decodeBoolForKey:@"zkshouldclipcontent"];
		self.drawsBorder                 = [dec decodeBoolForKey:@"zkdrawsborder"];
		self.attributedPlaceholderString = [dec decodeObjectForKey:@"zkattributedplaceholderstring"];
		self.drawsBackground             = [dec decodeBoolForKey:@"zkdrawsbackground"];
		self.target                      = [dec decodeObjectForKey:@"zktarget"];
		self.action                      = NSSelectorFromString([dec decodeObjectForKey:@"zkaction"]);
		self.continuous                  = [dec decodeBoolForKey:@"zkcontinuous"];
		self.placeholderStringAttributes = [[dec decodeObjectForKey:@"zkplaceholderstringattributes"] mutableCopy];
		self.stringAttributes            = [[dec decodeObjectForKey:@"zkstringattributes"] mutableCopy];
		self.selectedStringAttributes    = [dec decodeObjectForKey:@"zkselectedstringattributes"];
        self.style                       = [dec decodeIntegerForKey:@"zkStyle"];
        self.borderWidth                 = [dec decodeFloatForKey:@"zkBorderWidth"];
	}
	return self;
}

- (void)dealloc
{
	[self endEditing];
	[self discardCursorRects];

	self.attributedPlaceholderString = nil;
}

- (void)_instantiate
{
	self.hasHoverCursor    = YES;
	self.notEditingBackgroundColor   = [NSColor lightGrayColor];
	self.editingBackgroundColor   = [NSColor whiteColor];
    self.editingStringAttributes = @{};
    self.notEditingStringAttributes = @{NSForegroundColorAttributeName:NSColor.whiteColor};
	self.drawsBackground   = YES;
	self.drawsBorder       = YES;
	self.secure            = NO;
	self.shouldClipContent = YES;
	self.shouldShowFocus   = YES;
	self.placeholderString = nil;
	self.editable          = YES;
	self.selectable        = YES;
    self.alignment = NSLeftTextAlignment;
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
	style.lineBreakMode = NSLineBreakByTruncatingTail;
	self.stringAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
							 [NSColor controlTextColor], NSForegroundColorAttributeName,
							 DefaultFont, NSFontAttributeName,
							 style, NSParagraphStyleAttributeName, nil];



	self.placeholderStringAttributes = [@{NSForegroundColorAttributeName: [NSColor grayColor],
										NSFontAttributeName: DefaultFont,
										NSParagraphStyleAttributeName: style} mutableCopy];
	self.string            = @"";
    self.borderWidth = 1.0;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:self.attributedPlaceholderString forKey:@"zkattributedplaceholderstring"];
	[coder encodeObject:self.attributedString forKey:@"zkattributedstring"];
	[coder encodeObject:self.notEditingBackgroundColor forKey:@"zkDeselectedBackgroundcolor"];
	[coder encodeObject:self.editingBackgroundColor forKey:@"zkSelectedBackgroundcolor"];
	[coder encodeObject:self.notEditingStringAttributes forKey:@"zkDeselectedForegroundcolor"];
	[coder encodeObject:self.editingStringAttributes forKey:@"zkSelectedForegroundcolor"];
	[coder encodeBool:self.isSecure forKey:@"zksecure"];
	[coder encodeBool:self.isEditable forKey:@"zkeditable"];
	[coder encodeBool:self.isSelectable forKey:@"zkselectable"];
	[coder encodeBool:self.shouldShowFocus forKey:@"zkshouldshowfocus"];
	[coder encodeBool:self.shouldClipContent forKey:@"zkshouldclipcontent"];
	[coder encodeBool:self.drawsBorder forKey:@"zkdrawsborder"];
	[coder encodeBool:self.drawsBackground forKey:@"zkdrawsbackground"];
	[coder encodeBool:self.isContinuous forKey:@"zkcontinuous"];
	[coder encodeObject:self.placeholderStringAttributes forKey:@"zkplaceholderstringattributes"];
	[coder encodeObject:self.stringAttributes forKey:@"zkstringattributes"];
	[coder encodeObject:self.selectedStringAttributes forKey:@"zkselectedStringAttributes"];
	[coder encodeInteger:self.style forKey:@"zkStyle"];
	[coder encodeFloat:self.borderWidth forKey:@"zkBorderWidth"];

	if ([self.target conformsToProtocol:@protocol(NSCoding)]) {
		[coder encodeObject:NSStringFromSelector(self.action) forKey:@"zkaction"];
		[coder encodeObject:self.target forKey:@"zktarget"];
	}
}

// For mouse hover stuff
- (void)resetCursorRects
{
	[self discardCursorRects];

	if (self.hasHoverCursor) {
		NSCursor *hoverCursor = self.hoverCursor;

		[hoverCursor setOnMouseEntered:YES];
		[hoverCursor setOnMouseExited:NO];

		NSPoint origin = [self textOffsetForHeight:self._lineHeight];
		NSRect textRect = NSMakeRect(origin.x, origin.y, self.textWidth, self._lineHeight);

		[self addCursorRect:textRect cursor:self.hoverCursor];
	}

}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

	[NSGraphicsContext saveGraphicsState];

	// Clip the context
	if (self.shouldClipContent) {
		self._currentClippingPath = self.clippingPath;

		if (self._currentClippingPath)
			[self._currentClippingPath addClip];

	}

	// Draw background
	if (self.drawsBackground && (self.string.length>0 || !self.transparentWhenEmpty)) {
		[self drawBackgroundWithRect:dirtyRect selected:(self._currentFieldEditor!=nil)];
    }

	// Draw frame
	if (self.drawsBorder)
		[self drawFrameWithRect:dirtyRect];

	// Draw interios
	[self drawInteriorWithRect:dirtyRect];

	// If we don't have an active edit session, draw the text ourselves.
	if (!self._currentFieldEditor) {
		NSAttributedString *currentString = (self.attributedString.length > 0) ?
        _notEditingAttributedString :
        self.attributedPlaceholderString;

		if (self.isSecure && self.attributedString.length > 0)
			currentString = self._bullets;

		NSRect textRect;
		textRect.origin      = [self textOffsetForHeight:self._lineHeight];
		textRect.size.width  = self.textWidth;
		textRect.size.height = self._lineHeight;

		textRect.origin.y += self._offset;

		// Draw the text
		[self drawTextWithRect:textRect andString:currentString];
	}

	// Draw focus ring
	if (self._currentFieldEditor && self.shouldShowFocus) {
		NSSetFocusRingStyle(NSFocusRingOnly);
		[self._currentClippingPath ? self._currentClippingPath : [NSBezierPath bezierPathWithRect:self.bounds] fill];
	}

	// Release the clipping path when done
	self._currentClippingPath = nil;

	[NSGraphicsContext restoreGraphicsState];
}

- (void)drawBackgroundWithRect:(NSRect)rect selected:(BOOL)selected
{
	[(selected?self.editingBackgroundColor:self.notEditingBackgroundColor) set];
	NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

- (void)drawFrameWithRect:(NSRect)rect
{
	// You need a line width double of what your inner stroke needs to be while clipping
	[[NSColor grayColor] setStroke];
	[self._currentClippingPath setLineWidth:self.borderWidth ];
	[self._currentClippingPath stroke];
}

- (void)drawInteriorWithRect:(NSRect)rect
{
	// Do nothing by default
}

- (void)drawTextWithRect:(NSRect)rect andString:(NSAttributedString *)string
{	
	[string drawWithRect:rect options:0];
}


- (NSCursor *)hoverCursor
{
	return [NSCursor IBeamCursor];
}


- (NSColor *)insertionPointColor
{
	return nil;
}

#pragma mark - Dynamic Properties

- (NSString *)string
{
	return self.attributedString.string;
}

- (void)setString:(NSString *)string
{
    _isAttributedString = NO;
    if (string!=nil) {
        [self _setAttributedString:[[NSAttributedString alloc] initWithString:string attributes:self.stringAttributes]];
    }
    else {
        [ self _setAttributedString:nil ];
    }
}

-(void)setAlignment:(NSTextAlignment)alignment
{
    [self.stringAttributes[NSParagraphStyleAttributeName] setAlignment:alignment];
    [ self _setAttributedString:self.attributedString ];
}

-(NSTextAlignment)alignment
{
    return [self.stringAttributes[NSParagraphStyleAttributeName] alignment];
}

-(void)setToolTip:(NSString *)string
{
    self.string = string;
}

-(NSString *)toolTip
{
    return self.string;
}

- (NSAttributedString *)attributedString
{
	return _attributedString;
}

-(CGFloat)_lineHeightAndOffset:(CGFloat*)offset
{
    NSAttributedString* heightStr = [[NSAttributedString alloc] initWithString:@"ZGyyPh" attributes:self.stringAttributes];

	CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)heightStr);
	CGFloat ascent, descent, leading;
	CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

	CTFramesetterRef frame = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)heightStr);
	CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(frame, CFRangeMake(0, heightStr.length),
															   NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
    if (offset != nil) {
        *offset     = round(descent + leading);
    }

	CFRelease(frame);
	CFRelease(line);
	return size.height;
}

- (void)_setAttributedString:(NSAttributedString *)inAttrStr
{
	[self willChangeValueForKey:@"string"];
	[self willChangeValueForKey:@"attributedString"];


    NSMutableAttributedString* attributedString = [ inAttrStr mutableCopy ];
    [ self _adjustAttributedStringForBounds:attributedString ];
    self.stringAttributes[NSFontAttributeName] =
        [ self _adjustFontForBounds:self.stringAttributes[NSFontAttributeName]];
    
	_attributedString = [attributedString copy];
    _notEditingAttributedString = [ _attributedString mutableCopy ];
    if (!_isAttributedString) {
        for (NSString* key in _notEditingStringAttributes.allKeys) {
            [ _notEditingAttributedString removeAttribute:key range:NSMakeRange(0, _notEditingAttributedString.length)];
            [ _notEditingAttributedString addAttribute:key value:_notEditingStringAttributes[key] range:NSMakeRange(0, _notEditingAttributedString.length)];
        }
    }

    self._lineHeight = [ self _lineHeightAndOffset:&_offset ];

	// Generate a secure string
	NSString *bullets = [@"" stringByPaddingToLength:self.attributedString.length 
										  withString:[NSString stringWithFormat:@"%C", 0x2022]  // 0x2022 is the code for a bullet
									 startingAtIndex:0];

	NSMutableAttributedString *mar = self.attributedString.mutableCopy;
	[mar replaceCharactersInRange:NSMakeRange(0, mar.length) withString:bullets];
	self._bullets = mar;
    
	[self didChangeValueForKey:@"attributedString"];
	[self didChangeValueForKey:@"string"];
}

-(void)setAttributedString:(NSAttributedString *)attributedString
{
    _isAttributedString = YES;
    [self _setAttributedString:attributedString];
}

- (NSString *)placeholderString
{
	return self.attributedPlaceholderString.string;
}

-(void)setAttributedPlaceholderString:(NSAttributedString *)inAttrStr
{
    NSMutableAttributedString* attributedString = [ inAttrStr mutableCopy ];
    if (inAttrStr != nil) {
        [ self _adjustAttributedStringForBounds:attributedString ];
    }
    _attributedPlaceholderString = attributedString;
}

- (void)setPlaceholderString:(NSString *)placeholderString
{
	[self willChangeValueForKey:@"placeholderString"];
    if (placeholderString) {
        [self setAttributedPlaceholderString:[[NSAttributedString alloc] initWithString:placeholderString attributes:self.placeholderStringAttributes]];
    }
    else {
        self.attributedPlaceholderString=nil;
    }
	[self didChangeValueForKey:@"placeholderString"];
}

-(void)setStringAttributes:(NSMutableDictionary *)stringAttributes
{
    _stringAttributes = stringAttributes;
    _notEditingTotalStringAttributes = [ stringAttributes mutableCopy ];
    [_notEditingTotalStringAttributes addEntriesFromDictionary:self.notEditingStringAttributes];
}

- (NSBezierPath *)currentClippingPath
{
	return self._currentClippingPath;
}

#pragma mark - Mouse

- (void)beginEditing
{
	if (!self._currentFieldEditor)
		[self _configureFieldEditor];
}

- (void)endEditing
{
	if (self._currentFieldEditor) {		
		[self _setAttributedString:self._currentFieldEditor.attributedString];

        if (!self.isContinuous) {
            [ self propagateValue:self.string forBinding:NSToolTipBinding];
        }
		[self.window endEditingFor:self];

		[self._currentClipView removeFromSuperview];

		self._currentFieldEditor.layoutManager.glyphGenerator = [NSGlyphGenerator sharedGlyphGenerator];

		self._currentClipView    = nil;
		self._currentFieldEditor = nil;

		[self setNeedsDisplay:YES];
	}
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)becomeFirstResponder
{		
	BOOL success = [super becomeFirstResponder];

	if (success && !self._currentFieldEditor)
		[self _configureFieldEditor];

	return success;
}

- (BOOL)resignFirstResponder
{
	[self endEditing];
	return [super resignFirstResponder];
}

- (void)insertTab:(id)sender {
	self._currentFieldEditor.nextKeyView = self.nextKeyView;
	[self._currentFieldEditor insertTab:self];

	[self endEditing];
}

- (void)mouseDown:(NSEvent *)event
{
	if (!self._currentFieldEditor)
		[self _configureFieldEditor];

	[self._currentFieldEditor mouseDown:event]; // So you can just drag the selection right away
}

- (void)_configureFieldEditor
{
	if (![self.window makeFirstResponder:self.window])
		[self.window endEditingFor:nil]; // Free the field editor

	NSTextView *fieldEditor = (NSTextView *)[self.window fieldEditor:YES
														   forObject:self];

	fieldEditor.drawsBackground = NO;
	fieldEditor.fieldEditor = YES;
	fieldEditor.textStorage.attributedString = self.attributedString;

	NSRect fieldFrame;
    CGFloat lineHeight = [ self _lineHeightAndOffset:nil ];
	NSPoint fieldOrigin    = [self textOffsetForHeight:lineHeight];
	fieldFrame.origin      = fieldOrigin;
	fieldFrame.size.height = lineHeight;
	fieldFrame.size.width  = [self textWidth];

	NSSize layoutSize   = fieldEditor.maxSize;

	layoutSize.width    = FLT_MAX;
	layoutSize.height   = fieldFrame.size.height;

	fieldEditor.maxSize = layoutSize;
	fieldEditor.minSize = NSMakeSize(0.0, fieldFrame.size.height);

	fieldEditor.autoresizingMask = NSViewHeightSizable;
	fieldEditor.horizontallyResizable = YES;
	fieldEditor.verticallyResizable   = NO;

	NSDictionary *selectedStringAttrs = self.selectedStringAttributes;
	NSDictionary *stringAttrs         = self.stringAttributes;

	fieldEditor.textContainer.heightTracksTextView = YES;
	fieldEditor.textContainer.widthTracksTextView  = NO;
	fieldEditor.textContainer.containerSize        = layoutSize;
	fieldEditor.textContainerInset                 = NSMakeSize(0, 0);
	fieldEditor.textContainer.lineFragmentPadding  = 0.0;

	if (stringAttrs)
		fieldEditor.typingAttributes               = stringAttrs;

	if (selectedStringAttrs)
		fieldEditor.selectedTextAttributes         = selectedStringAttrs;

	fieldEditor.insertionPointColor                = self.insertionPointColor;

	fieldEditor.delegate         = self;
	fieldEditor.editable         = self.isEditable;
	fieldEditor.selectable       = self.isSelectable;
	fieldEditor.usesRuler        = NO;
	fieldEditor.usesInspectorBar = NO;
	fieldEditor.usesFontPanel    = NO;
	fieldEditor.nextResponder    = self.nextResponder;

	self._currentFieldEditor = fieldEditor;

	self._currentClipView = [[NSClipView alloc] initWithFrame:fieldFrame];
	self._currentClipView.drawsBackground = NO;
	self._currentClipView.documentView    = fieldEditor;

	fieldEditor.selectedRange             = NSMakeRange(0, fieldEditor.string.length); // select the whole thing

	if (self.isSecure)
		fieldEditor.layoutManager.glyphGenerator = [[ZKSecureGlyphGenerator alloc] init]; // Fuck yeah
	else
		fieldEditor.layoutManager.glyphGenerator = [NSGlyphGenerator sharedGlyphGenerator];
	//	fieldEditor.layoutManager.typesetterBehavior = NSTypesetterBehavior_10_2_WithCompatibility;

#
	if (fieldEditor.string.length > 0)
		self._offset = [fieldEditor.layoutManager.typesetter baselineOffsetInLayoutManager:fieldEditor.layoutManager glyphIndex:0];

	[self addSubview:self._currentClipView];
	[self.window makeFirstResponder:fieldEditor];

	[self setNeedsDisplay:YES];
}

-(void)_adjustAttributedStringForBounds:(NSMutableAttributedString*)attributedString
{
    __block NSFont* initialFont = self.stringAttributes[NSFontAttributeName] ?: DefaultFont;
    [attributedString enumerateAttributesInRange:NSMakeRange(0,attributedString.length)
                                         options:0
                                      usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
                                          if (attrs[NSFontAttributeName]) {
                                              initialFont = attrs[NSFontAttributeName];
                                              *stop = YES;
                                          }
                                      }];
    NSFont* font = [ self _adjustFontForBounds:initialFont ];
    
    [ attributedString removeAttribute:NSFontAttributeName range:NSMakeRange(0, attributedString.length)];
    [ attributedString addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributedString.length)];
}

-(NSFont*)_adjustFontForBounds:(NSFont*)initialFont
{
    if (initialFont==nil) { return nil; }
    CGFloat displayHeight = [ self _maximumTextHeight ];
    NSString *cacheKey = [ NSString stringWithFormat:@"%f%@",displayHeight,initialFont.fontName];
    static NSMutableDictionary *sCachedFonts = nil;
    if (sCachedFonts == nil ){ sCachedFonts = [NSMutableDictionary new]; }
    
    NSFont* cachedFont = sCachedFonts[cacheKey];
    if (cachedFont) { return cachedFont; }
    
    
    NSMutableAttributedString *attrString
    = [[NSMutableAttributedString alloc] initWithString:@"Tojjery" attributes:@{NSFontAttributeName:(initialFont?:DefaultFont)}];
    
    NSRange fullRange = NSMakeRange(0,attrString.length);

    // Try and fingd a size that fits without iterating too many times.
    // We start going 50 pixels at a time, then 10, then 1
    int offsets[] = { 10, 5, 1 };
    int size = MinimumFontSize-offsets[0];  // start at 24 (-26 + 50)
    NSFont* font = initialFont;
    for (size_t i = 0; i < sizeof(offsets) / sizeof(int); ++i) {
        for(size = size + offsets[i]; size >= MinimumFontSize && size < MaximumFontSize; size += offsets[i]) {
            font = [NSFontManager.sharedFontManager convertFont:initialFont toSize:size];
            [attrString addAttribute:NSFontAttributeName
                               value:font
                               range:fullRange];
            NSSize textSize = [attrString size];
            if ( textSize.height > displayHeight) {
                size = size - offsets[i];
                break;
            }
        }
    }

    // Bounds check our values
    if (size > MaximumFontSize) {
        size = MaximumFontSize;
    } else if (size < MinimumFontSize) {
        size = MinimumFontSize;
    }
    sCachedFonts[cacheKey] = font;
    return font;
}
#pragma mark - Layout

-(CGFloat)_maximumTextHeight
{
    return self.bounds.size.height - MAX(1.0,self.bounds.size.height/5.0) ;
}

- (NSPoint)textOffsetForHeight:(CGFloat)textHeight;
{
	// Default text rectangle
	return NSMakePoint([ self _radius], round((self.bounds.size.height - textHeight) / 2));
}

- (CGFloat)textWidth
{
	return self.bounds.size.width - [ self _radius ] * 2.0;
}

- (NSBezierPath *)clippingPath
{
    CGFloat radius = [ self _radius];
	return [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius];
}

-(CGFloat)_radius
{
    return (self.style == ZKTextFieldTokenStyle) ? self.bounds.size.height/2.0 : 4.0;
}

- (void)setFrame:(NSRect)frame
{
	CGFloat minH = self.minimumHeight;
	CGFloat minW = self.minimumWidth;
	CGFloat maxH = self.maximumHeight;
	CGFloat maxW = self.maximumWidth;

	//NSAssert(maxH >= minH || maxH <= 0, @"Maximum height of ZKTextField must be greater than the minimum!");
	//NSAssert(maxW >= minW || maxW <= 0, @"Maximum width of ZKTextField must be greater than the minimum!");

	CGFloat originalWidth  = frame.size.width;
	CGFloat originalHeight = frame.size.height;

	if (frame.size.height < minH && minH > 0)
		frame.size.height = minH;

	else if (frame.size.height > maxH && maxH > 0)
		frame.size.height = maxH;

	if (frame.size.width < minW && minW > 0)
		frame.size.width = minW;

	else if (frame.size.width > maxW && maxW > 0)
		frame.size.width = maxW;


	// Center the frame if we change the sides a bit

	CGFloat deltaX = originalWidth - frame.size.width;
	CGFloat deltaY = originalHeight - frame.size.height;

	frame.origin.x += round(deltaX / 2);
	frame.origin.y += round(deltaY / 2);

	[super setFrame:frame];
    
	if (self._currentClipView) { // Built in autoresizing sucks so much.
		[self._currentClipView setFrameSize:NSMakeSize(self.textWidth, self._currentClipView.frame.size.height)];
	}
}

- (CGFloat)minimumHeight
{
	return 12.0;
}

- (CGFloat)minimumWidth
{
	return 60.0;
}

- (CGFloat)maximumHeight
{
	return 48.0;
}

- (CGFloat)maximumWidth
{
	return 0.0;
}

#pragma mark - NSTextViewDelegate

- (void)textDidEndEditing:(NSNotification *)note
{	
	[self endEditing];
}

- (void)textDidChange:(NSNotification *)pNotification
{
	if (self.isContinuous) {
        
		self.string = self._currentFieldEditor.string;
        
        [ self propagateValue:self.string forBinding:NSToolTipBinding];

        if (self.target && [self.target respondsToSelector:self.action]) {
            [self.target performSelectorOnMainThread:self.action withObject:self waitUntilDone:YES];
        }
	}
}

- (BOOL)textView:(NSTextView *)inTextView doCommandBySelector:(SEL)inSelector
{
	if (inSelector == @selector(insertTab:)) {

		[self insertTab:self];

		return YES;

	} else if (inSelector == @selector(insertNewline:) || inSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
		self.attributedString = inTextView.attributedString;
		if (self.target && [self.target respondsToSelector:self.action])
			[self.target performSelectorOnMainThread:self.action withObject:self waitUntilDone:YES];

		return NO;
	}

	return NO;
}

@end
