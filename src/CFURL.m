//
// CFURL.m
//
// Copyright (c) 2012 Apportable. All rights reserved.
//
// Portions of this file are sourced from CFLite 635.12
// http://opensource.apple.com/tarballs/CF/CF-635.21.tar.gz
//

/*
 * Copyright (c) 2012 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/*  CFURL.c
  Copyright (c) 1998-2011, Apple Inc. All rights reserved.
  Responsibility: John Iarocci
*/

#import <CoreFoundation/CFURL.h>
#import <CoreFoundation/CFString.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSURL.h>

#define ToNSString(object) ((NSString *)object)
#define ToCFString(object) ((CFStringRef)object)

static NSString *notLegalURLCharacters(){
   unichar codes[]={
    0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
    0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,
    0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
    0x18,0x19,0x1A,0x1B,0x1C,0x1D,0x1E,0x1F,
    0x20,
    0x22,0x23,0x25,0x3C,0x3E,0x5B,0x5C,0x5D,
    0x5E,0x60,0x7B,0x7C,0x7D
   };
   NSUInteger length=32+1+8+5;
   
   return [NSString stringWithCharacters:codes length:length];
}

CFStringRef CFURLCreateStringByAddingPercentEscapes(CFAllocatorRef allocator,CFStringRef self,CFStringRef charactersToLeaveUnescaped,CFStringRef charactersToBeEscaped,CFStringEncoding encoding) {
   NSCharacterSet *dontEscapeSet=[NSCharacterSet characterSetWithCharactersInString:charactersToLeaveUnescaped?ToNSString(charactersToLeaveUnescaped):@""];
   NSCharacterSet *escapeSet=[NSCharacterSet characterSetWithCharactersInString:charactersToBeEscaped?ToNSString(charactersToBeEscaped):@""];
   NSCharacterSet *notLegalEscapeSet=[NSCharacterSet characterSetWithCharactersInString:notLegalURLCharacters()];
   NSUInteger i,length=[ToNSString(self) length],resultLength=0;
   unichar    unicode[length];
   unichar    result[length*3];
   const char *hex="0123456789ABCDEF";
      
   [ToNSString(self) getCharacters:unicode];
   
   for(i=0;i<length;i++){
    unichar code=unicode[i];

    if(([escapeSet characterIsMember:code] || [notLegalEscapeSet characterIsMember:code]) && ![dontEscapeSet characterIsMember:code]){
     result[resultLength++]='%';
     result[resultLength++]=hex[(code>>4)&0xF];
     result[resultLength++]=hex[code&0xF];
    }
    else {
     result[resultLength++]=code;
    }
   }
   
   if(length==resultLength)
    return CFRetain(self);
    
   return ToCFString([[NSString alloc] initWithCharacters:result length:resultLength]);
}

CFStringRef CFURLCreateStringByReplacingPercentEscapes(CFAllocatorRef allocator, CFStringRef originalString, CFStringRef charactersToLeaveEscaped) {
    return CFURLCreateStringByReplacingPercentEscapesUsingEncoding(allocator, originalString, charactersToLeaveEscaped, kCFStringEncodingUTF8);
}

// Lifted partially from Apple's CFLite

static inline Boolean _translateBytes(UniChar ch1, UniChar ch2, uint8_t *result) {
    *result = 0;
    if (ch1 >= '0' && ch1 <= '9') *result += (ch1 - '0');
    else if (ch1 >= 'a' && ch1 <= 'f') *result += 10 + ch1 - 'a';
    else if (ch1 >= 'A' && ch1 <= 'F') *result += 10 + ch1 - 'A';
    else return false;

    *result  = (*result) << 4;
    if (ch2 >= '0' && ch2 <= '9') *result += (ch2 - '0');
    else if (ch2 >= 'a' && ch2 <= 'f') *result += 10 + ch2 - 'a';
    else if (ch2 >= 'A' && ch2 <= 'F') *result += 10 + ch2 - 'A';
    else return false;

    return true;
}

static Boolean _appendPercentEscapesForCharacter(UniChar ch, CFStringEncoding encoding, CFMutableStringRef str) {
    uint8_t bytes[6]; // 6 bytes is the maximum a single character could require in UTF8 (most common case); other encodings could require more
    uint8_t *bytePtr = bytes, *currByte;
    CFIndex byteLength;
    CFAllocatorRef alloc = NULL;
    if (CFStringEncodingUnicodeToBytes(encoding, 0, &ch, 1, NULL, bytePtr, 6, &byteLength) != kCFStringEncodingConversionSuccess) {
        byteLength = CFStringEncodingByteLengthForCharacters(encoding, 0, &ch, 1);
        if (byteLength <= 6) {
            // The encoding cannot accomodate the character
            return false;
        }
        alloc = CFGetAllocator(str);
        bytePtr = (uint8_t *)CFAllocatorAllocate(alloc, byteLength, 0);
        if (!bytePtr || CFStringEncodingUnicodeToBytes(encoding, 0, &ch, 1, NULL, bytePtr, byteLength, &byteLength) != kCFStringEncodingConversionSuccess) {
            if (bytePtr) CFAllocatorDeallocate(alloc, bytePtr);
            return false;
        }
    }
    for (currByte = bytePtr; currByte < bytePtr + byteLength; currByte ++) {
        UniChar escapeSequence[3] = {'%', '\0', '\0'};
        unsigned char high, low;
        high = ((*currByte) & 0xf0) >> 4;
        low = (*currByte) & 0x0f;
        escapeSequence[1] = (high < 10) ? '0' + high : 'A' + high - 10;
        escapeSequence[2] = (low < 10) ? '0' + low : 'A' + low - 10;
        CFStringAppendCharacters(str, escapeSequence, 3);
    }
    if (bytePtr != bytes) {
        CFAllocatorDeallocate(alloc, bytePtr);
    }
    return true;
}

CFStringRef CFURLCreateStringByReplacingPercentEscapesUsingEncoding(CFAllocatorRef allocator, CFStringRef originalString, CFStringRef charactersToLeaveEscaped, CFStringEncoding enc) {
    CFMutableStringRef newStr = NULL;
    CFMutableStringRef escapedStr = NULL;
    CFIndex length;
    CFIndex mark = 0;
    CFRange percentRange, searchRange;
    Boolean escapeAll = (charactersToLeaveEscaped && CFStringGetLength(charactersToLeaveEscaped) == 0);
    Boolean failed = false;
    uint8_t byteBuffer[8];
    uint8_t *bytes = byteBuffer;
    int capacityOfBytes = 8;
    
    if (!originalString) return NULL;

    if (charactersToLeaveEscaped == NULL) {
        return (CFStringRef)CFStringCreateCopy(allocator, originalString);
    }

    length = CFStringGetLength(originalString);
    searchRange = CFRangeMake(0, length);

    while (!failed && CFStringFindWithOptions(originalString, CFSTR("%"), searchRange, 0, &percentRange)) {
        UniChar ch1, ch2;
        CFIndex percentLoc = percentRange.location;
        CFStringRef convertedString;
        int numBytesUsed = 0;
        do {
            // Make sure we have at least 2 more characters
            if (length - percentLoc < 3) { failed = true; break; }

            if (numBytesUsed == capacityOfBytes) {
                if (bytes == byteBuffer) {
                    bytes = (uint8_t *)CFAllocatorAllocate(allocator, 16 * sizeof(uint8_t), 0);
                    memmove(bytes, byteBuffer, capacityOfBytes);
                    capacityOfBytes = 16;
                } else {
                    void *oldbytes = bytes;
                    int oldcap = capacityOfBytes;
                    capacityOfBytes = 2*capacityOfBytes;
                    bytes = (uint8_t *)CFAllocatorAllocate(allocator, capacityOfBytes * sizeof(uint8_t), 0);
                    memmove(bytes, oldbytes, oldcap);
                    CFAllocatorDeallocate(allocator, oldbytes);
                }
            }
            percentLoc ++;
            ch1 = CFStringGetCharacterAtIndex(originalString, percentLoc);
            percentLoc ++;
            ch2 = CFStringGetCharacterAtIndex(originalString, percentLoc);
            percentLoc ++;
            if (!_translateBytes(ch1, ch2, bytes + numBytesUsed)) { failed = true;  break; }
            numBytesUsed ++;
        } while (CFStringGetCharacterAtIndex(originalString, percentLoc) == '%');
        searchRange.location = percentLoc;
        searchRange.length = length - searchRange.location;

        if (failed) break;
        convertedString = CFStringCreateWithBytes(allocator, bytes, numBytesUsed, enc, false);
        if (!convertedString) {
            failed = true;
            break;
        }

        if (!newStr) {
            newStr = CFStringCreateMutable(allocator, length);
        }
        if (percentRange.location - mark > 0) {
            // The creation of this temporary string is unfortunate. 
            CFStringRef substring = CFStringCreateWithSubstring(allocator, originalString, CFRangeMake(mark, percentRange.location - mark));
            CFStringAppend(newStr, substring);
            CFRelease(substring);
        }

        if (escapeAll) {
            CFStringAppend(newStr, convertedString);
        } else {
            CFIndex i, c = CFStringGetLength(convertedString);
            if (!escapedStr) {
                escapedStr = CFStringCreateMutableWithExternalCharactersNoCopy(allocator, &ch1, 1, 1, kCFAllocatorNull);
            }
            for (i = 0; i < c; i ++) {
                ch1 = CFStringGetCharacterAtIndex(convertedString, i);
                if (CFStringFind(charactersToLeaveEscaped, escapedStr, 0).location == kCFNotFound) {
                    CFStringAppendCharacters(newStr, &ch1, 1);
                } else {
                    // Must regenerate the escape sequence for this character; because we started with percent escapes, we know this call cannot fail
                    _appendPercentEscapesForCharacter(ch1, enc, newStr);
                }
            }
        }
        CFRelease(convertedString);
        mark = searchRange.location;// We need mark to be the index of the first character beyond the escape sequence
    }

    if (escapedStr) CFRelease(escapedStr);
    if (bytes != byteBuffer) CFAllocatorDeallocate(allocator, bytes);
    if (failed) {
        if (newStr) CFRelease(newStr);
        return NULL;
    } else if (newStr) {
        if (mark < length) {
            // Need to cat on the remainder of the string
            CFStringRef substring = CFStringCreateWithSubstring(allocator, originalString, CFRangeMake(mark, length - mark));
            CFStringAppend(newStr, substring);
            CFRelease(substring);
        }
        return newStr;
    } else {
        return (CFStringRef)CFStringCreateCopy(allocator, originalString);
    }
}

CFStringRef CFURLCopyPathExtension(CFURLRef self) {
   return (CFStringRef)[[[(NSURL *)self path] pathExtension] copy];
}

Boolean CFURLGetFileSystemRepresentation(CFURLRef self, Boolean resolveAgainstBase, uint8_t *buffer, CFIndex bufferLength) {
  // Not sure how to use resolveAgainstBase to figure out absolute path name
  NSString* filePath = [(NSURL *) self path];
  if (bufferLength < filePath.length) {
    return NO;
  }
  strncpy(buffer, filePath.UTF8String, bufferLength);
  return YES;
}

CFURLRef CFURLCreateFromFileSystemRepresentation(CFAllocatorRef allocator,const uint8_t *buffer,CFIndex length,Boolean isDirectory) {
  NSString* path;
  if (isDirectory) {
    path = [NSString stringWithFormat:@"%@/",[NSString stringWithCString:(char*)buffer encoding:[NSString defaultCStringEncoding]]];
  } else {
    path = [NSString stringWithCString:(char*)buffer encoding:[NSString defaultCStringEncoding]];
  }
   NSURL* url = [NSURL fileURLWithPath:path];
   return CFRetain((CFURLRef)url);
}

CFStringRef CFURLCopyUserName(CFURLRef url)
{
    return (CFStringRef)[[(NSURL *)url user] copy];
}

CFStringRef CFURLCopyPassword(CFURLRef url)
{
    return (CFStringRef)[[(NSURL *)url password] copy];
}

CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef allocator, CFStringRef path, CFURLPathStyle pathStyle, Boolean isDirectory) {
  // Are we really ever going to be using anything but kCFURLPOSIXPathStyle?
  return (CFURLRef)[[NSURL alloc] initFileURLWithPath:(NSString *)path isDirectory:(BOOL)isDirectory];
}

CFURLRef CFURLCreateWithFileSystemPathRelativeToBase(CFAllocatorRef allocator, CFStringRef path, CFURLPathStyle pathStyle, Boolean isDirectory, CFURLRef baseURL) {
  CFURLRef url = CFURLCreateWithFileSystemPath(allocator, path, pathStyle, isDirectory);
  CFURLRef fullURL = CFURLCreateWithString(allocator, CFURLGetString(url), baseURL);
  CFRelease(url);
  return fullURL;
}

CFURLRef CFURLCreateWithString(CFAllocatorRef allocator, CFStringRef string, CFURLRef baseURL) {
  return (CFURLRef)[[NSURL alloc] initWithString:(NSString *)string relativeToURL:(NSURL *)baseURL];
}

CFStringRef CFURLCopyLastPathComponent(CFURLRef self) {
  return (CFStringRef)[[((NSURL *)self) lastPathComponent] copy];
}

CFStringRef CFURLCopyFileSystemPath(CFURLRef self, CFURLPathStyle pathStyle) {
  return (CFStringRef)[[((NSURL *) self) path] copy];
}

CFStringRef CFURLGetString(CFURLRef self) {
  return [(NSURL *)self absoluteString];
}
