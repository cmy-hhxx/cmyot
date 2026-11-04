//
//  DefaultSettings+Encodings.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-08-09.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2014-2025 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreFoundation.CFString

extension DefaultSettings {
    
    /// Personal build: only the encodings that are actually used day to day.
    static let encodings: [UInt32] = ([
        CFStringBuiltInEncodings.UTF8,  // Unicode (UTF-8)
        kCFStringEncodingInvalidId,
        
        CFStringEncodings.GB_18030_2000,  // Chinese (GB18030, covers GBK/GB2312)
        CFStringEncodings.big5,           // Traditional Chinese (Big 5)
        kCFStringEncodingInvalidId,
        
        CFStringBuiltInEncodings.UTF16,          // Unicode (UTF-16)
        CFStringBuiltInEncodings.windowsLatin1,  // Western (Windows Latin 1)
    ] as [Any])
        .map { encoding in
            switch encoding {
                case let encoding as CFStringBuiltInEncodings:
                    encoding.rawValue
                case let encoding as CFStringEncodings:
                    UInt32(encoding.rawValue)
                case let encoding as UInt32 where encoding == kCFStringEncodingInvalidId:
                    encoding
                default:
                    preconditionFailure()
            }
        }
}
