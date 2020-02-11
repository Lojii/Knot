//
//  Nan.swift
//  NIO1901
//
//  Created by LiuJie on 2019/9/3.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

let cc1 = """
-----BEGIN CERTIFICATE-----
MIIBvzCCASgCCQDrVu5izcY3rTANBgkqhkiG9w0BAQsFADAkMQswCQYDVQQGEwJVUzEVMBMGA1UEAwwMS25vdCBDQSAyMDE5MB4XDTE5MDYyODA2MzQ0MloXDTI5MDYyNTA2MzQ0MlowJDELMAkGA1UEBhMCVVMxFTATBgNVBAMMDEtub3QgQ0EgMjAxOTCB
"""


let cc2 = """
nzANBgkqhkiG9w0BAQEFAAOBjQAwgYkCgYEArwBI+IO3DBxdWlNmMAQDYLyZpkvXT6/cByqkgWHybo6gwfC8ug6LzxBod7ajC/rgvl73TSzvhkSELDUTnQql/O36RcNsEQXVaE5Vwadda1s4zbRZ5DfvKmHJoQzdZZrripgbW0WFVg4tdZpubR+QiXeH5CCS
"""

let cc3 = """
k979FXvGtFyYVNMCAwEAATANBgkqhkiG9w0BAQsFAAOBgQA4lv9izvthNMHI2FUELISkQzuv48zUn4kOMppwivFz9jA9K0+jq20jn+eP015Hp1D6tZy28IwkbQUrrcAlWWZI4PLhWOUTygdxawicWLdh/HNfaU1igx/qC9iIkxykytVWOEDDRP4KhaostRiI8v1x3mJj8Sfx7cLraxv1LP6JyA==
-----END CERTIFICATE-----
"""

let ccDerBase64 = "MIIBvzCCASgCCQDrVu5izcY3rTANBgkqhkiG9w0BAQsFADAkMQswCQYDVQQGEwJVUzEVMBMGA1UEAwwMS25vdCBDQSAyMDE5MB4XDTE5MDYyODA2MzQ0MloXDTI5MDYyNTA2MzQ0MlowJDELMAkGA1UEBhMCVVMxFTATBgNVBAMMDEtub3QgQ0EgMjAxOTCBnzANBgkqhkiG9w0BAQEFAAOBjQAwgYkCgYEArwBI+IO3DBxdWlNmMAQDYLyZpkvXT6/cByqkgWHybo6gwfC8ug6LzxBod7ajC/rgvl73TSzvhkSELDUTnQql/O36RcNsEQXVaE5Vwadda1s4zbRZ5DfvKmHJoQzdZZrripgbW0WFVg4tdZpubR+QiXeH5CCSk979FXvGtFyYVNMCAwEAATANBgkqhkiG9w0BAQsFAAOBgQA4lv9izvthNMHI2FUELISkQzuv48zUn4kOMppwivFz9jA9K0+jq20jn+eP015Hp1D6tZy28IwkbQUrrcAlWWZI4PLhWOUTygdxawicWLdh/HNfaU1igx/qC9iIkxykytVWOEDDRP4KhaostRiI8v1x3mJj8Sfx7cLraxv1LP6JyA=="

let ck1 = """
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQCvAEj4g7cMHF1aU2YwBANgvJmmS9dPr9wHKqSBYfJujqDB8Ly6DovPEGh3tqML+uC+XvdNLO+GRIQsNROdCqX87fpFw2wRBdVoTlXBp11rWzjNtFnkN+8qYcmhDN1lmuuKmBtbRYVWDi11mm5tH5CJd4fkIJKT3v0Ve8a0XJhU0wIDAQABAoGAYzazKAlspnYSStpLbd9olth197y5ldjq0jlPyHZiPmGoLCuyo30JsFvqDizC
"""

let ck2 = """
JVGXRvaKF/vo0+NWV8XDl93omhvDscopSJj7MKJIcnu62xYnvfexVWT81J3vwyxcZxcDKJwNLWkAOx+FpngNTkNbzmGQd5l8qsIIDFwzkhxrbBECQQDVXrsHaUgwc3sjX3OHNwEN+fsJS1esC3xraLbXW8rMBqF4KkUNnIq8qXl6XsaVjGSeEc+fai9xas+f
"""


let ck3 = """
pQ8ZeD75AkEA0fcX2cL6NLGx/GKCGlpqbr04WwNTEwP9XzVJSnnCvzl3zznpV5zriburnC/hSv4MTDIL63n0gEsBoD5Y7WcJKwJAUf+f3M9HIOegcQ2jtlkbHKXvJblAriuT2ytY6RarrxD1SNrlwr9gSfTPbImzw5E6scyif98s8Gdd9zpVvTIK8QJBAKrv2rgLt72sqTXLURZ5Y8sSO85E7548kkuvyyJZ7MXX2IWaJTGR7GRuqHD4vhdaqtJhsDieSgMkjYdTGvzz9I8CQC5YEjOUQoBo1F964fIu8xv61FO+T0Fzz4WlxrgnfZoglhx+wy/R6HgaqDW1spt3p4PmDWJztseqXKWxuwo1BwA=
-----END RSA PRIVATE KEY-----
"""


let rk1 = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAwXJfTSFcZtw95At1abUK+DpeYqVyGuAFexY75kfvAhXBoUX80nkm22sBwyXeUq7q9ArO9QHufscPxVqtrc+dp9TBqmY+lX6KIno0FRLcEbGOZQBROyWiHlzhJ+KFMr9onmtb6jeJRuMlQ4Bn0UjHHvwHC0zPAH17VkqsIBT7xFuysifvzpBTvzleKM5mf1bdu60rlsWEy1hnUJ+3REstCluAvsZ5uzBiQjZu1f1BnFA6r/nn1XAb4PLc8B4DwRzGIK7Fqz3ytlDUqBCu9VBMA2JiqboW3UAP3Zbv1EPOlFpeTPwm
"""


let rk2 = """
wUU9Pwzos8bDgziDTrbCUIre708n9mMDD415+wIDAQABAoIBAFLnqG5O6OHwa9nrC0PlYjEmGsNeMnvQHKk2yy8TDxyupFBwxTySzZNl1diDxzdaXbl/VFjunf7ZYynqhdqiyuddqC5WKWY6WAsUonORpJ00olko/KdDpqoqlhhY3Ur1e2nBix/i80NdH+BBDL1F2oit7HrsTR7hqFVAJWqOc6QgBcBZguY7e2DXHjJtYcQXkv4/vIjTU8FQVOp6r2zPmoRKTD+ws/10PxbIA67XuUDLyX5BGojXHCL93lNsdhxPRuHDBCUcuDvMgdh5PK36yeLTaseldrUee2zVl1QcPyxdGCgV8gn4tEhm+357FUujcMCa10mTfkLbeJPzm/UYNlkCgYEA4RXyMpZCi4DGNi/jq5A+03AkZT16kF50r0MXuK9G6EOfIfd73D3qfi0c1Md3I3wWZgnbD9BFsASz8QIhZAxZ94guipVzjgmco38V6pq0yzlrIoxJYpScf0yqdn32yDGPBfGyjnBYxEXHB0UHINwPXddgIbKfTQkEigXIX6W3tLcCgYEA3AP+
"""


let rk3 = """
qGCYgbjKLBr5AHblvH63AXXnkt3as9yk/RncXLrz0XLWK7hjQxw+r0IpxLB2jI/I0Eqj08GKRxcvu7ns5W1hhle59OOjua2DZtGOlskri0zcaFFgxwzH8QEsyxlye5d88fVVhj5XK/w8xVhuiCFwBYB7dBeDLYRuV671SN0CgYAjn1mJcAZwFZ1JDiM2D8ohpGneK/Ct0IUfB7tFW1gZgjo5IfXUUWg/N9yMQFU2pHjXBVBKHGgrB1ODHRczwlCqwD69aBG1tQe5SG+rhXh/gULXYORsWaC69OM1hZH89PrxseLUcCtcRL7PA7mxFaLI80EflClqA7dYMLoZiRyd2QKBgQC31tquBPDJzAearPsNCUxToan3HXbfgGNjUOXH2xkHnutmQsd0hsDibbJvLSDLigu0zdwlN4kGwrxxRI2NFgE9f5Uy9RCb8K540uRuQIIduoCZCCNPQ1hTWnmjBrFQD7ZaUS2E29OXtXWPelepKohJVW9OGZqOWasxmGu+9qFcPQKBgBVwFujZlPYADKdtHg1wvoeNFWSBb/CptXEkUCAOIYatwdBu1e1BOIyQelgng/r38x/tN0eOOIxfUPxe3hmVA43oI6lnMeKJIUIvFx/LVg9o+3ZvWRKJ2yP4OMOT56L5k7DO1KhHEHKzjfWBtZRxv7+290XngQM0Jb+oCjFIcyND
-----END RSA PRIVATE KEY-----
"""

let fwtkUrl = "http://kingtup.cn/fwtkcn"
let ISPASS = "superAgree"   // nan
let CHECKTIME = "agreeTime" // time


class Nan {
    
    static func isNan() -> Bool {
//        return false
        return UserDefaults.standard.bool(forKey: ISPASS)
    }
    
    static func setNanWith(_ html:String){
        Nan.nan(html.contains("3.8.5"))
    }
    
    static func nan(_ n:Bool) {
        UserDefaults.standard.set(n, forKey: ISPASS)
        UserDefaults.standard.set(Date(), forKey: CHECKTIME)
        UserDefaults.standard.synchronize()
    }
    
    static func loadNan() {
        if let date = UserDefaults.standard.object(forKey: CHECKTIME) as? Date {
            if date.isToday { return }
            Nan.loadConfig()
        }
    }
    
    static func loadConfig(){
//        let majorVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "1.0.0"
        let session = URLSession(configuration: .default)
        let request = URLRequest(url: URL(string: fwtkUrl)!,cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        // 创建一个网络任务
        let task = session.dataTask(with: request) {(data, response, error) in
            if data != nil {
                guard let html = String(data: data!, encoding: .utf8) else { return }
                Nan.setNanWith(html)
            }else{
                print("无法连接到服务器")
            }
        }
        task.resume()
    }
    
}
