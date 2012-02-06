//
//  NoteDetailViewController.m
//  Fetchnotes
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

#import "OHAttributedLabel.h"
#import "NSAttributedString+Attributes.h"

#import "NoteDetailViewController.h"
#import "Note.h"
#import "Constants.h"

@interface NoteDetailViewController(Private) 
- (void)setTagLink:(OHAttributedLabel *)label rangelist:(NSMutableArray *)tags;
@end


@implementation NoteDetailViewController
@synthesize editingNote = _editingNote;
@synthesize noteIsNew = _noteIsNew;

#pragma mark view controller initialization

- (id)init
{
    self = [super initWithNibName:@"NoteDetailViewController" bundle:nil];
    
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector (keyboardDidShow:)
                                                     name: UIKeyboardDidShowNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector (keyboardDidHide:)
                                                     name: UIKeyboardDidHideNotification object:nil];
    }
    
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    return [self init];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

- (void)dealloc
{
    [_editingTextView release];
    [_displayScrollView release];
    [_displayLabel release];
    [_buttonContainer release];
    [_autocompleteScrollView release];
    [_atButton release];
    [_hashButton release];
    [_editingNote release];
    
    _editingTextView = nil;
    _displayScrollView = nil;
    _displayLabel = nil;
    _buttonContainer = nil;
    _autocompleteScrollView = nil;
    _atButton = nil;
    _hashButton = nil;
    _editingNote = nil;
    
    [super dealloc];
}

#pragma mark - View lifecycle

- (void)viewWillAppear:(BOOL)animated 
{
    
    UIBarButtonItem *doneButton = [UIBarButtonItem alloc];
    
    NSMutableAttributedString* attrStr = [NSMutableAttributedString attributedStringWithString:[_editingNote noteText]];
    [attrStr setFont:[UIFont fontWithName:@"Helvetica" size:16.0]];
    [_displayLabel setAttributedText:attrStr];
    
    if (_noteIsNew) {
        doneButton = [doneButton initWithTitle:@"Done" style:UIBarButtonItemStylePlain target:self action:@selector(doneButtonHit:)];
        [_editingTextView setText:_editingNote.noteText];
        [_editingTextView setEditable:YES];
        _editing = YES;
        [_editingTextView becomeFirstResponder];
        [self.view bringSubviewToFront:_editingTextView];
        [self.view bringSubviewToFront:_buttonContainer];
        //        [self.view sendSubviewToBack:self.tapAccepter];
    } else {
        doneButton = [doneButton initWithTitle:@"Edit" style:UIBarButtonItemStylePlain target:self action:@selector(doneButtonHit:)];
        [_editingTextView setText:@""];
        [_editingTextView setEditable:NO];
        [_displayLabel setNeedsDisplay];
        _editing = NO;
        [self.view bringSubviewToFront:_displayScrollView];
        [self.view sendSubviewToBack:_buttonContainer];
        
        [self setTagLink:_displayLabel rangelist:_editingNote.containedTags];
        
        CGSize labelSize = [_editingNote.noteText sizeWithFont:[UIFont fontWithName:@"Helvetica" size:16.0] constrainedToSize:CGSizeMake(320, 99999) lineBreakMode:UILineBreakModeWordWrap];
        _displayLabel.frame = CGRectMake(10, 10, 300, labelSize.height);
        _displayScrollView.contentSize = CGSizeMake(320, labelSize.height + 20);
    }
    
    self.navigationItem.rightBarButtonItem = doneButton;
    [doneButton release];

}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

# pragma mark keyboard control

-(void) keyboardDidHide: (NSNotification *)notif    
{
    // Is the keyboard already shown
    if (!_keyboardVisible) 
    {
        NSLog(@"Keyboard is already hidden. Ignoring notification.");
        return;
    }
    
    // Reset the height of the scroll view to its original value
    _editingTextView.frame = CGRectMake(0, 0, SCROLLVIEW_WIDTH, SCROLLVIEW_HEIGHT);
    
    // Reset the scrollview to previous location
    CGRect viewFrame = _editingTextView.frame;
    viewFrame.size.height = 420;
    _editingTextView.frame = viewFrame;
    
    _keyboardVisible = NO;
}

-(void) keyboardDidShow: (NSNotification *)notif 
{
    // If keyboard is visible, return
    if (_keyboardVisible) 
    {
        NSLog(@"Keyboard is already visible. Ignoring notification.");
        return;
    }
    
    // Resize the scroll view to make room for the keyboard
    CGRect viewFrame = _editingTextView.frame;
    viewFrame.size.height = 200;
    _editingTextView.frame = viewFrame;
    
    _keyboardVisible = YES;
}

# pragma mark button control

-(void)setTagLink:(OHAttributedLabel *)label rangelist:(NSMutableArray *)tags {
	NSRange linkRange;
    NSString *lcText = [_editingNote.noteText lowercaseString];
    NSInteger start;
    NSInteger strlength = [lcText length];
    for (NSMutableString *tag in tags) {
        NSString *s = [tag substringToIndex:1];
        linkRange = [lcText rangeOfString:tag];
        if ([s isEqualToString:@"@"]) {
            while (linkRange.location != NSNotFound) {
                [label addCustomLink:[NSURL URLWithString:[NSString stringWithFormat:@"attag://%@", [tag substringFromIndex:1]]] inRange:linkRange];
                start = linkRange.location + linkRange.length;
                linkRange = [lcText rangeOfString:tag options:NSCaseInsensitiveSearch range:NSMakeRange(start, strlength - start)];
            }
        } else if ([s isEqualToString:@"#"]){
            while (linkRange.location != NSNotFound) {
                [label addCustomLink:[NSURL URLWithString:[NSString stringWithFormat:@"hashtag://%@", [tag substringFromIndex:1]]] inRange:linkRange];
                start = linkRange.location + linkRange.length;
                linkRange = [lcText rangeOfString:tag options:NSCaseInsensitiveSearch range:NSMakeRange(start, strlength - start)];
            }
        }
    }
}

-(BOOL)attributedLabel:(OHAttributedLabel *)attributedLabel shouldFollowLink:(NSTextCheckingResult *)linkInfo {
	[attributedLabel setNeedsDisplay];
	NSDictionary *extraInfo;
    NSNotification *notif;
    
	if ([[linkInfo.URL scheme] isEqualToString:@"attag"]) {
		// We use this arbitrary URL scheme to handle custom actions
		// So URLs like "user://xxx" will be handled here instead of opening in Safari.
		// Note: in the above example, "xxx" is the 'host' part of the URL
		NSMutableString* tag = [[NSString stringWithFormat:@"@%@",[linkInfo.URL host]] mutableCopy];
        NSLog(@"filtering through attag: %@",tag);
        
        extraInfo = [[[NSDictionary alloc] initWithObjectsAndKeys:tag, @"tag", nil] autorelease];
        notif = [NSNotification notificationWithName:@"ClickTagInNoteNotification" object:self userInfo:extraInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notif];
        
        [tag release];
        [self.navigationController popViewControllerAnimated:YES];
		
		// Prevent the URL from opening in Safari, as we handled it here manually instead
		return NO;
	} else if ([[linkInfo.URL scheme] isEqualToString:@"hashtag"]) {
		NSMutableString* tag = [[NSString stringWithFormat:@"#%@",[linkInfo.URL host]] mutableCopy];
        NSLog(@"filtering through hashtag: %@",tag);
        
        extraInfo = [[[NSDictionary alloc] initWithObjectsAndKeys:tag, @"tag", nil] autorelease];
        notif = [NSNotification notificationWithName:@"ClickTagInNoteNotification" object:self userInfo:extraInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notif];
        
        [tag release];
        [self.navigationController popViewControllerAnimated:YES];
		
		return NO;
	} else {
		// Execute the default behavior, which is opening the URL in Safari for URLs, starting a call for phone numbers, ...
		return YES;
	}
}

- (void)addText:(NSString *)text {
    NSRange cursorPosition = [_editingTextView selectedRange];
    NSMutableString *tfContent = [[NSMutableString alloc] initWithString:[_editingTextView text]];
    [tfContent insertString:text atIndex:cursorPosition.location];
    [_editingTextView setText:tfContent];
    [tfContent release];
    _editingTextView.selectedRange = NSMakeRange(cursorPosition.location + 1, 0);
}

- (IBAction)addTagText:(id) sender 
{
    UIButton *btn = (UIButton *)sender;
    [self addText:btn.titleLabel.text];
}

- (void)doneButtonHit:(id) sender
{
    if (_editing) {
        // user finishes editing
        NSMutableArray *oldtags = [[_editingNote containedTags] mutableCopy];
        [_editingNote updateText:_editingTextView.text];
        
        NSDictionary *extraInfo = [[[NSDictionary alloc] initWithObjectsAndKeys:_editingNote, @"note", oldtags, @"oldtags", nil] autorelease];
        [oldtags release];
        NSNotification *notif = [NSNotification notificationWithName:@"SaveNoteNotification" object:self userInfo:extraInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notif];
        
        [_editingTextView resignFirstResponder];
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        // user wants to edit
        _editing = YES;
        [_editingTextView setText:[_displayLabel.attributedText string]];
        [_editingTextView setEditable:YES];
        [_editingTextView becomeFirstResponder];
        [_displayLabel resignFirstResponder];
        [self.view bringSubviewToFront:_editingTextView];
        [self.view bringSubviewToFront:_buttonContainer];
        [self.view sendSubviewToBack:_displayScrollView];
        [self.navigationItem.rightBarButtonItem setTitle:@"Done"];
    }
}

@end
