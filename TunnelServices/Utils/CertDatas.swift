//
//  CertDatas.swift
//  TunnelServices
//
//  Created by 果叔叔 on 2021/10/15.
//  Copyright © 2021 Lojii. All rights reserved.
//

import Foundation

public class CertDatas: NSObject {
    public static let cacert = """
    -----BEGIN CERTIFICATE-----
    MIIDoDCCAogCCQDt7jfMjrGv2zANBgkqhkiG9w0BAQUFADCBkDELMAkGA1UEBhMC
    Q04xDjAMBgNVBAgMBUh1YmVpMQ4wDAYDVQQHDAVXdWhhbjERMA8GA1UECgwIcGFu
    Z29saW4xETAPBgNVBAsMCHBhbmdvbGluMRUwEwYDVQQDDAxwYW5nb2xpbi5jb20x
    JDAiBgkqhkiG9w0BCQEWFXBhbmdvbGluQHBhbmdvbGluLmNvbTAgFw0yMTA4MjQx
    NTM3MjhaGA8yMTIxMDczMTE1MzcyOFowgZAxCzAJBgNVBAYTAkNOMQ4wDAYDVQQI
    DAVIdWJlaTEOMAwGA1UEBwwFV3VoYW4xETAPBgNVBAoMCHBhbmdvbGluMREwDwYD
    VQQLDAhwYW5nb2xpbjEVMBMGA1UEAwwMcGFuZ29saW4uY29tMSQwIgYJKoZIhvcN
    AQkBFhVwYW5nb2xpbkBwYW5nb2xpbi5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IB
    DwAwggEKAoIBAQDBZ8FpnmAhBYgA7RA2ixIJkV7uln/2CyYvagWhFmd+SVL+kx4i
    hj2y9gUhgpp87RPTHPbaOBW3dOi/lv4voF9MIauC6tlQDOO1aDcqB34ju6yvK+Fs
    7RXmkfJ6L+z0QJZYOXWTpeafTzcNwIXz3i+rcT6EEQxhY/z6IDGf5BMhndB83Rjq
    +FRsBw/EDQIowrxsvIVM4LwKSAAMF1xIaTZMDLt+kI3/JmSXZq0D1CXdjpCAZ/Vh
    RvxUCOgwg6YMj/82vdoczy6/j6fjhbxUPNCz6Ory+m46sO1H5gFnpVepDWc26G4Q
    1OIdzSYfcCtun34p9UfMg8XOS7Ggb6CnQNXDAgMBAAEwDQYJKoZIhvcNAQEFBQAD
    ggEBAL1pwWeRuuqDReZ9EasOfVx6hkLmh7xLttLshSrg+4VSy37vNuWiRMXJEZjx
    jl1MJiX7KKkRp98VBFm18AiBvVE5QFAmQKr0VSlw//2xeeomEjEkh7rFxW3i8aqH
    kTeku1k0gGo2on/N2DaO2s+Ya2lz+QGlTeqUTKxOvnAGerwuj9WMzyR+n/l6BRQ5
    A1Fy+ELn5O++gtvRPJfsKyVESl0REsiCqz2VkUmFvRxP25Qv63OBZ4kfGwcy8BJu
    QhUxUQPR0tJD4j+m+M/6XfyDvkIZZZeDkUhR37vCVEyK9Dfuo/qkrtpB/b/NUrR9
    XVXlhlixJBEf+OgnesNihIXFqUE=
    -----END CERTIFICATE-----

    """

    public static let cakey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEAwWfBaZ5gIQWIAO0QNosSCZFe7pZ/9gsmL2oFoRZnfklS/pMe
    IoY9svYFIYKafO0T0xz22jgVt3Tov5b+L6BfTCGrgurZUAzjtWg3Kgd+I7usryvh
    bO0V5pHyei/s9ECWWDl1k6Xmn083DcCF894vq3E+hBEMYWP8+iAxn+QTIZ3QfN0Y
    6vhUbAcPxA0CKMK8bLyFTOC8CkgADBdcSGk2TAy7fpCN/yZkl2atA9Ql3Y6QgGf1
    YUb8VAjoMIOmDI//Nr3aHM8uv4+n44W8VDzQs+jq8vpuOrDtR+YBZ6VXqQ1nNuhu
    ENTiHc0mH3Arbp9+KfVHzIPFzkuxoG+gp0DVwwIDAQABAoIBACqYkW6TpRRgxX1+
    uM1qf8R/serWVsR33CchMLAz4QNdXtwWxtJPwpMBwEuLGj9db7pVbMDPDWlkZEae
    GMmghpyb5cxlsQsCa7xugYfOMqfoE7ZY8cMtzF8F0eO7XnLFLtergAvOxCZeKf/r
    YRU+4DzgKiaoIpPok7T7FjLi5pvGZfE2sEuQ9kVzsUb+zfvtMU8hGdveaTgz9IpO
    74ZArp2rD6Jf6GTS3ZFKfioKteT/qCORyZdBf1QK4LqfWOlKszAjRPdEmhsiehuM
    bCbq/FUc6xeznDiOfxcaPFtfRWOTDPYENLJmvvmyp21M/TeOfWMNKmarBGwUZL1e
    X88ibcECgYEA8D3EY2Scv3zkbTVzoeos0O/DRN3VJ+MT4I2eWH2y1ABwUb/yfShV
    UkSYUz2q4EbMvJKkktX8TQWx89FM/LuxlJsggdwKrlOn22SfvDnwPHHzW19v6b86
    LXg0oJru6xVHonI4Hm3ldk/6swdJLDz9xDDZccyUcA4qIIq2553ErfECgYEAzhd/
    sUOBrm5We1k2bX96aEWziDYkx6W178ef9z/NGyH5CtUCHjwH529uRGkaaQfHPB+I
    DjWJfrfCGejy/U1B8RoialWGuIrlwUAsxZ8V3APurPixtxj7PiItQVfW8DK2wSqv
    Vzd3Lsjc0qf7rTV3yDSVzDZk+cCvJ9gfbaH5WvMCgYEAu3gnuTv5CYBnLEVqv23i
    nQSMR0AoJuEPUMqSRxGHq+HPxCtaCYqg0frPNx3HKw50k66HGEI9iMkp7U5lmk7J
    K2LGQi+4cgK72PsznwlDS5fMRIA775aWyoaj4rQkPnQzmzMwUaaGSgXtZykHU6sg
    h6lq9V+kcbDL9OrqAeHeabECgYA4x7CengK0lCGvijy8nkqTP+DevkwT1Uvy7ATe
    ke1odEuw+E7FFbT3xnOS1YI5PbNelTFe+NEQ4H/Rs6R+tTJdwt2IflfHsDzsqUms
    iM/09gBkF4Ce+Xr++1uMjS7irpY7Ug9M8DMd6KkuQKnOZtTBi/tZcAMR7ExVpe3C
    vsV8kQKBgEBYHGr1cLk6EIRT6cdcw4J8n1L1zQdwmboBhf4AeWW9SnIL0NqZwfJ5
    6caolOVtJTynmfSNjkPg8PEFUF+vLoI2TEEFwrrC2d99E2Cle3T3AeGePoTplC/F
    mF9Heo+qvZms827GgjHoBuaIAwjDn2nUNV53PoYCIL7t/001A1M+
    -----END RSA PRIVATE KEY-----

    """

    public static let rsakey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEAwNHsmEi/9hl8Jkr357ZW2oZb64KM/5mrVmdUosi6eJMXFcAv
    vV9Ir9Xt6W9AaaFju917lGeIIqxCC0iJFK6ArxoWnDDEuamGAUBQfAd1TE+eWJ7s
    pFH46S8oZYkosGS0Zww88s39Cw2QddFx7v8waYXlD2KL+fk3hKuo6L6pSJrG+9+S
    nz5cWbvh4k7i1TcSjrbHhrhPV8aipKx5H0BsD2lm9ymjIWZ3nO9YTFf+t4n51le0
    pElBUoHc50XtlcDuBs6B9MJM3zB6zh5m22L0u7LtpYJQpw5a1StRojzYT7Z2Gv88
    imKaRQzbXlyJgknXlAZ3U4+jSYTulgtN43iQDwIDAQABAoIBAQCJ24zUs+7K/R2O
    IztrJyqhwj4l+4jjlfKyK96PJARuAHwYyPdY5a8KSGF47FmZLBIqVwfr6rmiUJZH
    iuy3JKxMhNJ1iUidlV6BtoHUq2Bp1uLXaYi3UwQrc9PmBFJbCyUQJ+fLkQrBxEjs
    c3qJ7VmnmFtUzJhXeJ8A89onzWkqxn8cemsk+qbalhYz1CCr0JIripQRAhMpx4n2
    UoICnxp+a1AF7FF3FUxNm9GxCHjpRqBOr6EBnEQV3o35GWs+iLwYFGCR+naES/0f
    ZUnbSkNa4o/f7yTEu+cds9Rb6jI/4cqNuKRV2mH7YOdfSH5/JBKrkvxWzseQTUsW
    H050mowBAoGBAPTQpAMq7PhFo+AUCbyym6H35PRIdUNE5+a0P+zChepFjtsWYj7u
    myDK61OlER5sIJtEwEhof9GtZo95BGy/WQZEoaOEbodlT93XZWgQJdIjB/xOinvk
    jVOE1qOJDrMi7rZcQNeWXUUhVG8+/NHVNgMyOQPFwDYDyly1xUJyO61PAoGBAMmh
    JkbFRyRpFF/8oclBU9ARygDmHLxfTR7+eUP/L7+mPkwk++N1aaHlPyjRRM+tA9OA
    2f4JtkK+qWCe3OgTtP4WysijJL0MEXiq1OsI2Fnb/XL3E8ddI/8AHBwzgCb0ovoZ
    M98J+C1gi/S10aI3nnZ0ZDO620fc7un5N9CAh8FBAoGAV3TBYrBO/1JBfKcr41Ea
    7/2SuQG5glJ3VZ9Gxtmm5U37/qA8cKbknA5hivwI5YlTDKS+3B8Yqlr7rH1a605g
    CzExXSzOH2g9484y174NBMim7adRKXk4U4G8+6bWrX/pLxQ9xcZdg3iopSUnQ/6a
    0QF8BLD8PU+VVxFIarhMQVkCgYEAxy1uBlMzaAB1pCyIFat3A//OsPygPmVWZdu0
    JzubC5NJzyZpvdRquQchUU0I0K51LSYIMi+d4GlAILZOOuPc03PodjLTQ/z79Vus
    YVGnh30N7detri+QM4MEQceOPO1FYhIrb5UFmK3bE63YnIqc+x8XLRLVMzRIvtD2
    Ff4iHQECgYAyzrxmtUZFTtEvYoaVY3FkLJghxWPQlZoSsqGPCn3tSRsELngSQlCl
    A563M1PoG7piKW0vAh76jq0GUIwd8pic1b1DRPzODFF7sNauulgnSs1tqE8xixlf
    78if5xHA0YRTjZWACbGbFlPmuUJiltIdOaL56v2dssvOgTZ1X0Ae0w==
    -----END RSA PRIVATE KEY-----

    """

    public static let cader = "MIIDoDCCAogCCQDt7jfMjrGv2zANBgkqhkiG9w0BAQUFADCBkDELMAkGA1UEBhMCQ04xDjAMBgNVBAgMBUh1YmVpMQ4wDAYDVQQHDAVXdWhhbjERMA8GA1UECgwIcGFuZ29saW4xETAPBgNVBAsMCHBhbmdvbGluMRUwEwYDVQQDDAxwYW5nb2xpbi5jb20xJDAiBgkqhkiG9w0BCQEWFXBhbmdvbGluQHBhbmdvbGluLmNvbTAgFw0yMTA4MjQxNTM3MjhaGA8yMTIxMDczMTE1MzcyOFowgZAxCzAJBgNVBAYTAkNOMQ4wDAYDVQQIDAVIdWJlaTEOMAwGA1UEBwwFV3VoYW4xETAPBgNVBAoMCHBhbmdvbGluMREwDwYDVQQLDAhwYW5nb2xpbjEVMBMGA1UEAwwMcGFuZ29saW4uY29tMSQwIgYJKoZIhvcNAQkBFhVwYW5nb2xpbkBwYW5nb2xpbi5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDBZ8FpnmAhBYgA7RA2ixIJkV7uln/2CyYvagWhFmd+SVL+kx4ihj2y9gUhgpp87RPTHPbaOBW3dOi/lv4voF9MIauC6tlQDOO1aDcqB34ju6yvK+Fs7RXmkfJ6L+z0QJZYOXWTpeafTzcNwIXz3i+rcT6EEQxhY/z6IDGf5BMhndB83Rjq+FRsBw/EDQIowrxsvIVM4LwKSAAMF1xIaTZMDLt+kI3/JmSXZq0D1CXdjpCAZ/VhRvxUCOgwg6YMj/82vdoczy6/j6fjhbxUPNCz6Ory+m46sO1H5gFnpVepDWc26G4Q1OIdzSYfcCtun34p9UfMg8XOS7Ggb6CnQNXDAgMBAAEwDQYJKoZIhvcNAQEFBQADggEBAL1pwWeRuuqDReZ9EasOfVx6hkLmh7xLttLshSrg+4VSy37vNuWiRMXJEZjxjl1MJiX7KKkRp98VBFm18AiBvVE5QFAmQKr0VSlw//2xeeomEjEkh7rFxW3i8aqHkTeku1k0gGo2on/N2DaO2s+Ya2lz+QGlTeqUTKxOvnAGerwuj9WMzyR+n/l6BRQ5A1Fy+ELn5O++gtvRPJfsKyVESl0REsiCqz2VkUmFvRxP25Qv63OBZ4kfGwcy8BJuQhUxUQPR0tJD4j+m+M/6XfyDvkIZZZeDkUhR37vCVEyK9Dfuo/qkrtpB/b/NUrR9XVXlhlixJBEf+OgnesNihIXFqUE="

}