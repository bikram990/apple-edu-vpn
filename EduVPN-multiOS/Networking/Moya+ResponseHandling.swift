//
//  Moya+ResponseHandling.swift
//  eduVPN
//
//  Created by Jeroen Leenarts on 04-08-17.
//  Copyright © 2017 SURFNet. All rights reserved.
//

import Moya
import PromiseKit

let signedAtDateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return dateFormatter
}()

extension Moya.Response {
    
    func mapResponse<T: Decodable>() -> Promise<T> {
        return Promise(resolver: { seal in
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let result = try decoder.decode(T.self, from: self.filterSuccessfulStatusCodes().data)
                seal.fulfill(result)
            } catch {
                seal.reject(error)
            }
        })
    }
}
