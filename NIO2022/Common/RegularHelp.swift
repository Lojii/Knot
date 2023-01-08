//
//  RegularHelp.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class RegularHelp: NSObject {
    
}
enum ValidatedType {
    case Email
    case PhoneNumber
    case Number
    case SpecificNumbers
    case Chinese
    case IllegalCharacter
    case URL
    case BlankLines
    case QQ
    case ID
    case MAC
    case IdCard
    case DateInformation
    case AccountLegal
    case Password
    case StrongPassword
    case ThereIsNo
}

func ValidateText(validatedType type: ValidatedType, validateString: String) -> Bool {
    do {
        let pattern: String
        
        switch type {
            
        case ValidatedType.Email:
            pattern = "^([a-z0-9_\\.-]+)@([\\da-z\\.-]+)\\.([a-z\\.]{2,6})$"
            
        case ValidatedType.PhoneNumber:
            pattern = "^1[0-9]{10}$"
            
        case ValidatedType.Number:
            pattern = "^[0-9]*$"
            
        case ValidatedType.SpecificNumbers:
            pattern = "^\\d{n}$"
            
        case ValidatedType.Chinese:
            pattern = "^[\\u4e00-\\u9fa5]{0,}$"
            
        case ValidatedType.IllegalCharacter:
            pattern = "[%&',;=?$\\\\^]+"
            
        case ValidatedType.URL:
            pattern = "^http://([\\w-]+\\.)+[\\w-]+(/[\\w-./?%&=]*)?$"
            
        case ValidatedType.BlankLines:
            pattern = "^s*|s*$"
            
        case ValidatedType.QQ:
            pattern = "[1-9][0-9]{4,}"
            
        case ValidatedType.ID:
            pattern = "([1-9]{1,3}\\.){3}[1-9]"
            
        case ValidatedType.MAC:
            pattern = "([A-Fa-f0-9]{2}\\:){5}[A-Fa-f0-9]"
            
        case ValidatedType.IdCard:
            pattern = "\\d{14}[[0-9],0-9xX]"
            
        case ValidatedType.DateInformation:
            pattern = "^\\d{4}-\\d{1,2}-\\d{1,2}"
            
        case ValidatedType.AccountLegal:
            pattern = "^[a-zA-Z][a-zA-Z0-9_]{4,15}$"
            
        case ValidatedType.Password:
            pattern = "^[a-zA-Z]\\w{5,17}$"
            
        case ValidatedType.StrongPassword:
            pattern = "^(?=.*\\d)(?=.*[a-z])(?=.*[A-Z]).{8,10}$"
            
        default:
            pattern = ""
        }
        
        let regex: NSRegularExpression = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
        let matches = regex.matches(in: validateString, options: NSRegularExpression.MatchingOptions.reportProgress, range: NSMakeRange(0, validateString.count))
        return matches.count > 0
    }
    catch {
        return false
    }
}


/*
 * 验证邮箱
 */

func EmailIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.Email, validateString: vStr)
}

/*
 * 验证手机号
 */
func PhoneNumberIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.PhoneNumber, validateString: vStr)
}

/*
 * 验证只能输入数字
 */
func NumberIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.Number, validateString: vStr)
}

/*
 * 验证输入几位数字   里面的n换成你想要的数字
 */
func SpecificNumbersIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.SpecificNumbers, validateString: vStr)
}

/*
 * 验证是否是中文
 */
func ChineseIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.Chinese, validateString: vStr)
}

/*
 * 验证是否含有^%&',;=?$\"等字符
 */
func IllegalCharacterIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.IllegalCharacter, validateString: vStr)
}

/*
 * 验证URL
 */
func URLIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.URL, validateString: vStr)
}

/*
 * 验证QQ号
 */
func QQIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.QQ, validateString: vStr)
}

/*
 * 验证ID地址
 */
func IDIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.ID, validateString: vStr)
}

/*
 * 验证MAC地址
 */
func MACIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.MAC, validateString: vStr)
}

/*
 * 验证身份证号
 */
func IdCardIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.IdCard, validateString: vStr)
}


/*
 * 验证帐号是否合法(字母开头，允许5-16字节，允许字母数字下划线)
 */
func AccountLegalIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.AccountLegal, validateString: vStr)
}
/*
 * 验证密码(以字母开头，长度在6~18之间，只能包含字母、数字和下划线)
 */
func PasswordIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.Password, validateString: vStr)
}
/*
 * 验证强密码(必须包含大小写字母和数字的组合，不能使用特殊字符，长度在8-10之间)
 */
func StrongPasswordIsValidated(vStr: String) -> Bool {
    return ValidateText(validatedType: ValidatedType.StrongPassword, validateString: vStr)
}
