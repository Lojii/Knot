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
MIIDUTCCAjmgAwIBAgIJAIF6vBDF/R46MA0GCSqGSIb3DQEBCwUAMF8xCzAJBgNVBAYTAkNOMRAwDgYDVQQIDAdCZWlKaW5nMRAwDgYDVQQHDAdCZWlKaW5nMQ0wCwYDVQQKDARURVNUMQwwCgYDVQQLDAN3ZWIxDzANBgNVBAMMBkNNQl9DQTAeFw0yMDAzMTgwNDM4NTVaFw0yMjA2MjEwNDM4NTVaMF8xCzAJBgNVBAYTAkNOMRAwDgYDVQQIDAdCZWlKaW5nMRAwDgYDVQQHDAdCZWlKaW5nMQ0wCwYDVQQKDARURVNUMQwwCgYDVQQLDAN3ZWIxDzANBgNVBAMMBkNNQl9DQTCCASIwDQYJKoZIhvcNAQEBBQADggEP
"""


let cc2 = """
ADCCAQoCggEBANmNgOYKD2OPR/HvWT56q8Ww12FsP6YDl1q8eaP0LGAU3LB/c7It//hs1m7W63N7j27nZf2GJUhUbOdZrmdHFRijmpFFZc/3E2WcHo2AjEOdkN3L3cWWW5w+xAsFYLXbt3fgOSEXwBU3PP8b8Eq+hRAoAvLbeN72oa6ottBle98ITpMA6FQeWfMOzyzswclR5i/+N2qyIU7HcyVsUHl1E1iTo86EYzVbPaSSUuzFmdbWsSu/DLOLnaEnOJAL6R1EIlhDnIzdZZIjFl2sp6iCKwp80W6sieFx++YjZMFYUaOu8NuqlOAfF/TxYnonzcFxzG9IlfFWLAxOhGkwjuzgoMsCAwEAAaMQMA4wDAYDVR0TBAUwAwEB
"""

let cc3 = """
/zANBgkqhkiG9w0BAQsFAAOCAQEAPDPw9uJS3/3t1rLFGDEgyhwmbHSuBbwLh3GxxMBbtHijV3B7CVYWm5BTGoVPXCXl8DCeUTnbtGfz34efbh8ADqQHFQk/dRR9cfoNfxvXzC00+AmY58sLlyFWx/JAiB4N46Qt/8FqR5gex+8R02D9tuHZ5hmTu/+vdsUXrIPGHOzA6foG//h31sX6oIyIcFZ8cTxMMOPEFJEdoeqmhrx7r6gUAhNCwo4tKHvR8M8Vfr047oBa9Aq19OE1Sg/zITJPX7QMQJQ1aq9ruRpAAtPJG5lO2FZvIf6tpSNqHFtB+lB7OpTKzS33ECYUA96DXwFe3MsMeULuB9sGb5/GJlOyxA==
-----END CERTIFICATE-----
"""

let ccDerBase64 = "MIIDUTCCAjmgAwIBAgIJAIF6vBDF/R46MA0GCSqGSIb3DQEBCwUAMF8xCzAJBgNVBAYTAkNOMRAwDgYDVQQIDAdCZWlKaW5nMRAwDgYDVQQHDAdCZWlKaW5nMQ0wCwYDVQQKDARURVNUMQwwCgYDVQQLDAN3ZWIxDzANBgNVBAMMBkNNQl9DQTAeFw0yMDAzMTgwNDM4NTVaFw0yMjA2MjEwNDM4NTVaMF8xCzAJBgNVBAYTAkNOMRAwDgYDVQQIDAdCZWlKaW5nMRAwDgYDVQQHDAdCZWlKaW5nMQ0wCwYDVQQKDARURVNUMQwwCgYDVQQLDAN3ZWIxDzANBgNVBAMMBkNNQl9DQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANmNgOYKD2OPR/HvWT56q8Ww12FsP6YDl1q8eaP0LGAU3LB/c7It//hs1m7W63N7j27nZf2GJUhUbOdZrmdHFRijmpFFZc/3E2WcHo2AjEOdkN3L3cWWW5w+xAsFYLXbt3fgOSEXwBU3PP8b8Eq+hRAoAvLbeN72oa6ottBle98ITpMA6FQeWfMOzyzswclR5i/+N2qyIU7HcyVsUHl1E1iTo86EYzVbPaSSUuzFmdbWsSu/DLOLnaEnOJAL6R1EIlhDnIzdZZIjFl2sp6iCKwp80W6sieFx++YjZMFYUaOu8NuqlOAfF/TxYnonzcFxzG9IlfFWLAxOhGkwjuzgoMsCAwEAAaMQMA4wDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAPDPw9uJS3/3t1rLFGDEgyhwmbHSuBbwLh3GxxMBbtHijV3B7CVYWm5BTGoVPXCXl8DCeUTnbtGfz34efbh8ADqQHFQk/dRR9cfoNfxvXzC00+AmY58sLlyFWx/JAiB4N46Qt/8FqR5gex+8R02D9tuHZ5hmTu/+vdsUXrIPGHOzA6foG//h31sX6oIyIcFZ8cTxMMOPEFJEdoeqmhrx7r6gUAhNCwo4tKHvR8M8Vfr047oBa9Aq19OE1Sg/zITJPX7QMQJQ1aq9ruRpAAtPJG5lO2FZvIf6tpSNqHFtB+lB7OpTKzS33ECYUA96DXwFe3MsMeULuB9sGb5/GJlOyxA=="

let ck1 = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA2Y2A5goPY49H8e9ZPnqrxbDXYWw/pgOXWrx5o/QsYBTcsH9zsi3/+GzWbtbrc3uPbudl/YYlSFRs51muZ0cVGKOakUVlz/cTZZwejYCMQ52Q3cvdxZZbnD7ECwVgtdu3d+A5IRfAFTc8/xvwSr6FECgC8tt43vahrqi20GV73whOkwDoVB5Z8w7PLOzByVHmL/43arIhTsdzJWxQeXUTWJOjzoRjNVs9pJJS7MWZ1taxK78Ms4udoSc4kAvpHUQiWEOcjN1lkiMWXaynqIIrCnzRbqyJ4XH75iNkwVhRo67w26qU4B8X9PFieifNwXHMb0iV8VYsDE6EaTCO7OCgywIDAQABAoIBAFztXrPkdDJYz6h+Tqari5gEM9v/eyiUvCAcBfGMqS/ZeXNC3c6sa3xYMThjQWuwydHbsesbU+2TcnlYC3E+IbrGl42aESVGKtjqWPqkgEWZlnnHTVHLKhKRlPgIMgk8cyAXfQ+vr3Lgh4OJ
"""

let ck2 = """
EZk7zGbcUHYgXX8P5nxOwNg/oSvg/Jd9PUp8n19K7Om+jHQjE1MKZG57D2SCY7Y66GXLQSlHse/nEkosY8KRffTmYg1wcyrXF/+dlTSeesaVRRN+VOlICtLRLeLST1ioaUAZXibM6st09Lb4jcvKRPXBKKw7QkAWAH+tkDBdc3/oyc4JmErrJFG6UywHOBOzHVurMvECgYEA+Q+amm3UZoGRAuQpOB4LpTMvp2TG9xH10l0vl1WK2reWIoxLoFn4+BmOTFPzi2Hqp5GNKl61XgXTd3+gw+zE0DLzfCpWLX1nIxAhb7qKo3GJGLAaM5VUjlPauiD1/RImPhAZ1Y8hbjoFdrS5Kz7nq4VSG4q67Z6OS1QO3e+etZUCgYEA350r1+8WRAc51PKIeo43bQcko3BQZjaVhrtpFo6suQRnpZXn5qNt/vRe8FEMhQxftsG8EqoWtj/vzo1ax3dktKzwsLNU7zcP4UddOIv3JK+C/PFrSYN3UIY6+qAJF2CABlR2BVT+6G18jn/72geaJbN7sEF9qUq0UMJcMLLZpN8CgYBw1cPqMNXodsy2rZ2LAfmu
"""


let ck3 = """
p0jwonSNnMJswrD789JLkp7fGgZtKDXmWNWh+Oq+e+bucb+tsWijpyoN2nGAMfVciajL2PZf949RUE6FqtKCh75fw/Cq6/152b2fU61+MMnIlkzN9uFjab/t7qRxVjdo+qafObPEUXAP6o4tuBCEHQKBgBA8AvDcZMtvkt1I9mufY5rAyAItp0ikcdqkRI7ksNmF3liBN6Lg/p1h9HqSB8ypB1HnYtYgDyIQJkLitFKC8obDf330pxfu8XIzkisGzlyVeXcPt/BQYRsxg5qqf754vRK4kxD0CMWrHT3jQM+leaV/EF3Ng2gFCm5KjhLjCTYVAoGBALrWIwzv+gqLOqKJRuH1cJN8wPaRqoSsi5xJZ0KR22ov6V9TSNscxl5DgKyHVkgr9lOtk9euc1gXFEc/w0FvCvqOvYmJLYD0mGLxd9tM/j+wOsw14tGvOX7Ebi12/ZmaUW0v0pEpjYd+o9Yf9auKzEElxF4uwnHumjbQRLvP2YyY
-----END RSA PRIVATE KEY-----
"""


let rk1 = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAykkFIbQfCiYCMtjegRzbWMfPuRuZPzx7hfTm3HTW6+M4uvdc
fcLMJZ+31s88evxu+Dza8xtuBY9xG6d0++IIfzwBejssr80+Y1rv6HY+uDoeGyJu
YOSAu/gOEBwXog+kq6k6VVVE/cPlOCBkjCQn3645GvvKUDJoFJLysWkxGEPvVXGJ
6L8vA2cpVhbG/P3v2mUaFQjxLLSor/f1orBKMZmmrWp71Lq+RmxGMaOUevmnuBaa
8Gnpm+HuDd8n4r2u3uogtvoMbHDSQYks4Gpdi8uapYD+K6aFCcfo4T4JZDIJpVk1
zoWjOe9iQvd2EN6I7Z7nfHZvZEkajPiZKBLHHQIDAQABAoIBAQClEgFGB55swad5
ps+rvMiiIiu4enULzWdfYQIjVJUt2TYqHEE1vwioizWR7XsFQYmsuLxTNkcJ8ovy
bSxhf4o/idAK1s8YhvwqR8MOh6+W1pZKvkYke1MyELIpI0OF1A4kpuwbRoIOMxWS
P5zNX5PKTHn9MwtddkTIxUGW1Khji1hQ8AcC7+EBhcWBsCa7ko8Hj8biPKs61lJ7
LP/Vmw9Oz6l3syN+8iFYUfTs+Zx2YhRTvwrJ4gW+jWpufQtP2AX09B8/OXK5u4T1
BtaCyiv2LWEWyzTjHhuPOYPbLDkmNPKOzXcTZP8dvTwqB80G9M/Ft8bRMmCPQrRx
TJVYJbBhAoGBAPKfeHHy9W2MeBiAV8TFO4H2U2+/5O6N7Ev9/ws1cs3tLs3ATwAi
JLHpiNqdYRBS+Oqlr010vtZP2kIpKm7qZ8Mi2w6V3wTk+rYHezss2h3KzB+fvXSa
5TWHvsbHKczk0fjQQObc6jZp01TtRxKa7Cxm3MNkCMT7NFc25eqivjovAoGBANVw
Ms3Osc17fyxfFQQ6x1GK7Lfq5Omni3K1HW84YTDbJnOjyg2qv0CCK+zd++6nYMTH
j0BEWQL7D1NgK6hAC62O+d+t36AA3SrkGl98CGx6/SXpZ7o1LZ1CSf1a1cHKLIR2
49EG11ge5jNdZ9MYf7aVWc33TDnawy14TbNI9pxzAoGAT/jkmJq+7ycYBut3ArMI
VGQ/SFx2N3OsabgFM0qg1uPRQ5yZ7a9TbRlPNNAfSGQxDBck22EZ7kZP6PLsu7ak
ERwSHJKl+lUHlqyMoAq+sodAFURwDFlqJ+Tgq2DGlHTwCRWL7wzuXpUvRZUYkjdi
lZgqOHVmtpcev4im7FpMXZ0CgYBuyq3kfS14b2mlO7nqFyTNpCKamZi33Nua8H7V
89snhCqijlvc2kwqjSeF7fjPehzWKIyonJHj5TSgX+Rpks09C2GThWr2YFxt3jf+
ZqDsxq7PVigc1WvXHMjRdaxNysdu/1PkdfukZ22xLgQt5KKuwTn7myn7Qh5cZP1Y
WkCBFwKBgGGSiZ5SXvR4OOGgHW/Dow1+FpZfvt8XWPcyA7vYM+RYdph3KnPSIvcy
h6RmmURqG/b43PVYLpztSfEzNMrzppkdKChcIkQlMv6Jg+vztGAvKr/zZICYDvFk
KRfPeB1rOA8Kp143HzfDwnqcemb2FrbCl8oB1cYHzqJI3r9J4Oa3
-----END RSA PRIVATE KEY-----

"""


let rk2 = """
"""


let rk3 = """
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
