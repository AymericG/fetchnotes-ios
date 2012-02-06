//
//  NoteCell.m
//  fetchnotes
//
// Common Public Attribution License Version 1.0. 
// “The contents of this file are subject to the Common Public Attribution 
// License Version 1.0 (the “License”); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://www.fetchnotes.com/license. The License is based on the Mozilla 
// Public License Version 1.1 but Sections 14 and 15 have been added to cover 
// use of software over a computer network and provide for limited attribution 
// for the Original Developer. In addition, Exhibit A has been modified to be 
// consistent with Exhibit B. 
// Software distributed under the License is distributed on an “AS IS” basis, 
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for 
// the specific language governing rights and limitations under the License. 
// The Original Code is Fetchnotes. 
// The Original Developer is the Initial Developer. 
// The Initial Developer of the Original Code is Fetchnotes LLC. All portions 
// of the code written by Fetchnotes LLC are Copyright (c) 2011 Fetchnotes LLC. 
// All Rights Reserved. 

#import "NoteCell.h"
#import "OHAttributedLabel.h"
#import "NSAttributedString+Attributes.h"

@implementation NoteCell

@dynamic note;

@synthesize noteTextLabel;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        OHAttributedLabel *label = [[OHAttributedLabel alloc] initWithFrame:CGRectMake(5, 3, 310, 38)];
        self.noteTextLabel = label;
		[self.contentView addSubview:self.noteTextLabel];
        [label release];
        UIView *tapAccepter = [[UIView alloc] initWithFrame:CGRectMake(5, 3, 310, 38)];
        [self.contentView addSubview:tapAccepter];
        [tapAccepter release];
    }
    return self;
}

- (Note *)note
{
    return self.note;
}   

- (void)setTagColor:(NSMutableArray *)tags {
	NSRange linkRange;
    NSString *str = [[noteTextLabel.attributedText string] lowercaseString];
    NSInteger start;
    NSInteger strlength = [str length];
    for (NSMutableString *tag in tags) {
        if (![tag isEqualToString:@"Untagged"]) {
            linkRange = [str rangeOfString:tag];
            while (linkRange.location != NSNotFound) {
                [noteTextLabel addCustomLink:[NSURL URLWithString:tag] inRange:linkRange];
                start = linkRange.location + linkRange.length;
                linkRange = [str rangeOfString:tag options:NSCaseInsensitiveSearch range:NSMakeRange(start, strlength - start)];
            }
            
        }
    }
    noteTextLabel.underlineLinks = NO;
}

- (void)setNote:(Note *)newNote
{
    
    note = newNote;
    
    NSMutableAttributedString* attrStr = [NSMutableAttributedString attributedStringWithString:note.noteText];
    [attrStr setFont:[UIFont fontWithName:@"Helvetica" size:16.0]];
    [self.noteTextLabel setAttributedText:attrStr];
    [self.noteTextLabel setHighlightedTextColor:[UIColor whiteColor]];
    [self.noteTextLabel setHighlightedLinkColor:[UIColor whiteColor]];
    [self setTagColor:note.containedTags];
	
    [self setNeedsDisplay];
    
}

- (void)layoutSubviews {
    [super layoutSubviews];
	
    if (!self.editing) {
		CGRect frame = CGRectMake(10, 10, 300, 25);
		self.noteTextLabel.frame = frame;
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // Configure the view for the selected state
    UIColor *backgroundColor = nil;
	if (selected) {
	    backgroundColor = [UIColor clearColor];
	} else {
		backgroundColor = [UIColor whiteColor];
	}
    
	self.noteTextLabel.backgroundColor = backgroundColor;
	self.noteTextLabel.highlighted = selected;
	self.noteTextLabel.opaque = !selected;
}

- (void)dealloc
{
    [super dealloc];
}

@end
