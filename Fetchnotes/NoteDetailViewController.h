//
//  NoteDetailViewController.h
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

#import <UIKit/UIKit.h>
@class OHAttributedLabel;
@class Note;

@interface NoteDetailViewController : UIViewController
{
    IBOutlet UITextView         *_editingTextView;
    
    IBOutlet UIScrollView       *_displayScrollView;
    IBOutlet OHAttributedLabel  *_displayLabel;
    
	IBOutlet UIView             *_buttonContainer;
    IBOutlet UIScrollView       *_autocompleteScrollView;
    IBOutlet UIButton           *_atButton;
    IBOutlet UIButton           *_hashButton;
    
    Note                        *_editingNote;
    
    BOOL                        _keyboardVisible;
    BOOL                        _editing;
    BOOL                        _noteIsNew;
}

@property (nonatomic, retain) Note *editingNote;
@property (nonatomic, assign) BOOL noteIsNew;

- (IBAction)addTagText:(id)sender;

@end
