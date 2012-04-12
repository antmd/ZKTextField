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
@property (nonatomic, retain) NSBezierPath *_currentClippingPath;
@property (nonatomic, retain) NSTextView   *_currentFieldEditor;
@property (nonatomic, retain) NSClipView   *_currentClipView;
@property (nonatomic, assign) CGFloat       _offset;
@property (nonatomic, assign) CGFloat       _lineHeight;
- (void)_configureFieldEditor;
@end

#pragma mark - ZKTextField
#pragma mark -

@implementation ZKTextField

#pragma mark - Private Properties

@synthesize _currentClippingPath;
@synthesize _currentFieldEditor;
@synthesize _currentClipView;
@synthesize _lineHeight;
@synthesize _offset;

#pragma mark - Public Properties
@dynamic string;
@dynamic placeholderString;
@synthesize attributedString            = _attributedString;
@synthesize attributedPlaceholderString = _attributedPlaceholderString;
@synthesize backgroundColor             = _backgroundColor;
@synthesize drawsBackground             = _drawsBackground;
@synthesize drawsBorder                 = _drawsBorder;
@synthesize hasHoverCursor              = _hasHoverCursor;
@synthesize shouldClipContent           = _shouldClipContent;
@synthesize secure                      = _secure;
@synthesize shouldShowFocus             = _shouldShowFocus;
@synthesize editable                    = _editable;
@synthesize selectable                  = _selectable;

#pragma mark - Lifecycle

- (id)initWithFrame:(NSRect)frame
{
    if (([super initWithFrame:frame])) {		
		self.frame             = frame; // Recalculate frame

		self.hasHoverCursor    = YES;
		self.backgroundColor   = [NSColor whiteColor];
		self.drawsBackground   = YES;
		self.drawsBorder       = YES;
		self.secure            = NO;
		self.shouldClipContent = YES;
		self.shouldShowFocus   = YES;
		self.string            = @"";
		self.placeholderString = @"Username";
		self.editable          = YES;
		self.selectable        = YES;
		
    }
    
    return self;
}

- (void)dealloc
{
	[self endEditing];
	[self discardCursorRects];
	
	self._currentClippingPath        = nil;
	self.attributedString            = nil;
	self.attributedPlaceholderString = nil;
	self.backgroundColor             = nil;
	
	[super dealloc];
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
	if (self.drawsBackground)
		[self drawBackgroundWithRect:dirtyRect];
	
	// Draw frame
	if (self.drawsBorder)
		[self drawFrameWithRect:dirtyRect];
	
	// Draw interios
	[self drawInteriorWithRect:dirtyRect];
	
	// If we don't have an active edit session, draw the text ourselves.
	if (!self._currentFieldEditor) {
		NSAttributedString *currentString = (self.attributedString.length > 0) ? self.attributedString : self.attributedPlaceholderString;
		
		// If we are secure and there is actual non-placeholder content, replace it with bullets
		if (self.isSecure && (self.attributedString.length > 0)) {
			NSString *bullets = [@"" stringByPaddingToLength:currentString.length 
												  withString:[NSString stringWithFormat:@"%C", 0x2022]  // 0x2022 is the code for a bullet
											 startingAtIndex:0];
			
			NSMutableAttributedString *mar = [currentString.mutableCopy autorelease];
			[mar replaceCharactersInRange:NSMakeRange(0, mar.length) withString:bullets];
			currentString = mar;
		}
		
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

- (void)drawBackgroundWithRect:(NSRect)rect
{
	[self.backgroundColor set];
	NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

- (void)drawFrameWithRect:(NSRect)rect
{
	// You need a line width double of what your inner stroke needs to be while clipping
	[[NSColor grayColor] setStroke];
	[self._currentClippingPath setLineWidth:2.0];
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

- (NSDictionary *)stringAttributes
{
	NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	style.lineBreakMode = NSLineBreakByTruncatingTail;
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSColor controlTextColor], NSForegroundColorAttributeName,
			[NSFont systemFontOfSize:13.0f], NSFontAttributeName, 
			style, NSParagraphStyleAttributeName, nil];
}

- (NSDictionary *)placeholderStringAttributes
{
	NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	style.lineBreakMode = NSLineBreakByTruncatingTail;
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSColor grayColor], NSForegroundColorAttributeName,
			[NSFont systemFontOfSize:13.0f], NSFontAttributeName, 
			style, NSParagraphStyleAttributeName, nil];
}

- (NSCursor *)hoverCursor
{
	return [NSCursor IBeamCursor];
}

- (NSDictionary *)selectedStringAttributes
{
	return nil;
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
	[self setAttributedString:[[[NSAttributedString alloc] initWithString:string attributes:self.stringAttributes] autorelease]];
}

- (NSAttributedString *)attributedString
{
	return _attributedString;
}

- (void)setAttributedString:(NSAttributedString *)attributedString
{
	[self willChangeValueForKey:@"string"];
	[self willChangeValueForKey:@"attributedString"];
	
	if (_attributedString)
		[_attributedString release];
	_attributedString = [attributedString retain];
	
	[self didChangeValueForKey:@"attributedString"];
	[self didChangeValueForKey:@"string"];
	
	NSAttributedString *heightStr = attributedString;
	if (!attributedString || attributedString.length == 0)
		heightStr = [[[NSAttributedString alloc] initWithString:@"ZGyyPh" attributes:self.stringAttributes] autorelease];
	
	CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)heightStr);
	CGFloat ascent, descent, leading;
	CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
		
	CTFramesetterRef frame = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)heightStr);
	CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(frame, CFRangeMake(0, self.attributedString.length),
															   NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
	self._lineHeight = size.height;
	self._offset     = round(descent + leading);
		
	CFRelease(frame);
	CFRelease(line);
}

- (NSString *)placeholderString
{
	return self.attributedPlaceholderString.string;
}

- (void)setPlaceholderString:(NSString *)placeholderString
{
	[self willChangeValueForKey:@"placeholderString"];
	[self setAttributedPlaceholderString:[[[NSAttributedString alloc] initWithString:placeholderString attributes:self.placeholderStringAttributes] autorelease]];
	[self didChangeValueForKey:@"placeholderString"];
}

- (NSBezierPath *)currentClippingPath
{
	return self._currentClippingPath;
}

#pragma mark - Mouse

- (void)beginEditing
{
	if (!self._currentFieldEditor)
		[self _currentFieldEditor];
}

- (void)endEditing
{
	if (self._currentFieldEditor) {
		self.string = self._currentFieldEditor.string;
		
		[self._currentClipView removeFromSuperview];
		self._currentClipView    = nil;
		self._currentFieldEditor = nil;
		
		[self.window makeFirstResponder:nil];
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

- (void)mouseDown:(NSEvent *)event
{
	if (!self._currentFieldEditor)
		[self _configureFieldEditor];
	
	[self._currentFieldEditor mouseDown:event]; // So you can just drag the selection right away
}

- (void)_configureFieldEditor
{
	NSTextView *fieldEditor = (NSTextView *)[self.window fieldEditor:YES
														   forObject:self];
	fieldEditor.drawsBackground = NO;	
	fieldEditor.fieldEditor = YES;
	fieldEditor.string      = self.string;
		
	NSRect fieldFrame;
	NSPoint fieldOrigin    = [self textOffsetForHeight:self._lineHeight];
	fieldFrame.origin      = fieldOrigin;
	fieldFrame.size.height = self._lineHeight;
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
	
	self._currentFieldEditor = fieldEditor;
	
	self._currentClipView = [[[NSClipView alloc] initWithFrame:fieldFrame] autorelease];
	self._currentClipView.drawsBackground = NO;
	self._currentClipView.documentView    = fieldEditor;
	
	fieldEditor.selectedRange             = NSMakeRange(0, fieldEditor.string.length); // select the whole thing
		
	if (self.isSecure)
		fieldEditor.layoutManager.glyphGenerator = [[[ZKSecureGlyphGenerator alloc] init] autorelease]; // Fuck yeah
//	fieldEditor.layoutManager.typesetterBehavior = NSTypesetterBehavior_10_2_WithCompatibility;
	
	if (fieldEditor.string.length > 0)
		self._offset = [fieldEditor.layoutManager.typesetter baselineOffsetInLayoutManager:fieldEditor.layoutManager glyphIndex:0];
	
	[self addSubview:self._currentClipView];
	[self.window makeFirstResponder:fieldEditor];
	
	[self setNeedsDisplay:YES];
}

#pragma mark - Layout

- (NSPoint)textOffsetForHeight:(CGFloat)textHeight;
{
	// Default text rectangle
	return NSMakePoint(4.0, round((self.bounds.size.height - textHeight) / 2));
}

- (CGFloat)textWidth
{
	return self.bounds.size.width - 8.0;
}

- (NSBezierPath *)clippingPath
{
	return [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4.0 yRadius:4.0];
}

- (void)setFrame:(NSRect)frame
{
	CGFloat minH = self.minimumHeight;
	CGFloat minW = self.minimumWidth;
	CGFloat maxH = self.maximumHeight;
	CGFloat maxW = self.maximumWidth;
	
	NSAssert(maxH >= minH || maxH <= 0, @"Maximum height of ZKTextField must be greater than the minimum!");
	NSAssert(maxW >= minW || maxW <= 0, @"Maximum width of ZKTextField must be greater than the minimum!");
	
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
	return 24.0;
}

- (CGFloat)minimumWidth
{
	return 60.0;
}

- (CGFloat)maximumHeight
{
	return 24.0;
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

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString
{
	// No newlines
	if ([replacementString isEqualToString:@"\n"])
		return NO;
	return YES;
}

@end
