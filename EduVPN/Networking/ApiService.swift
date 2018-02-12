//
//  ApiService.swift
//  EduVPN
//
//  Created by Jeroen Leenarts on 02-08-17.
//  Copyright © 2017 SURFNet. All rights reserved.
//

import Foundation

import Moya

import PromiseKit
import AppAuth

enum ApiServiceError: Swift.Error {
    case noAuthState
}

enum ApiService {
    case profileList
    case userInfo
    case createConfig(displayName: String, profileId: String)
    case createKeypair(displayName: String)
    case profileConfig(profileId: String)
    case systemMessages
    case userMessages
}

extension ApiService {
    var path: String {
        switch self {
        case .profileList:
            return "/profile_list"
        case .userInfo:
            return "/user_info"
        case .createConfig:
            return "/create_config"
        case .createKeypair:
            return "/create_keypair"
        case .profileConfig:
            return "/profile_config"
        case .systemMessages:
            return "/system_messages"
        case .userMessages:
            return "/user_messages"
        }
    }

    var method: Moya.Method {
        switch self {
        case .profileList, .userInfo, .profileConfig, .systemMessages, .userMessages:
            return .get
        case .createConfig, .createKeypair:
            return .post
        }
    }

    var task: Task {
        switch self {
        case .profileList, .userInfo, .systemMessages, .userMessages:
            return .requestPlain
        case .createConfig(let displayName, let profileId):
            return .requestParameters(parameters: ["display_name": displayName, "profile_id": profileId], encoding: URLEncoding.httpBody)
        case .createKeypair(let displayName):
            return .requestParameters(parameters: ["display_name": displayName], encoding: URLEncoding.httpBody)
        case .profileConfig(let profileId):
            return .requestParameters(parameters: ["profile_id": profileId], encoding: URLEncoding.queryString)
        }
    }

    var sampleData: Data {
        return "".data(using: String.Encoding.utf8)!
    }
}

struct DynamicApiService: TargetType, AcceptJson {
    let baseURL: URL
    let apiService: ApiService

    var path: String { return apiService.path }
    var method: Moya.Method { return apiService.method }
    var task: Task { return apiService.task }
    var sampleData: Data { return apiService.sampleData }
}

class DynamicApiProvider: MoyaProvider<DynamicApiService> {
    let api: Api
    let authConfig: OIDServiceConfiguration
    private var credentialStorePlugin: CredentialStorePlugin

    var currentAuthorizationFlow: OIDAuthorizationFlowSession?

    public func authorize(presentingViewController: UIViewController) -> Promise<OIDAuthState> {
        let request = OIDAuthorizationRequest(configuration: authConfig, clientId: "org.eduvpn.app.ios", scopes: ["config"], redirectURL: URL(string: "org.eduvpn.app:/api/callback")!, responseType: OIDResponseTypeCode, additionalParameters: nil)
        return Promise(resolvers: { fulfill, reject in
            currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presentingViewController, callback: { (authState, error) in

                if let error = error {
                    print("Authorization error \(error.localizedDescription)")
                    reject(error)
                    return
                }

                self.api.authState = authState

                precondition(authState != nil, "THIS SHOULD NEVER HAPPEN")

                print("Got authorization tokens. Access token: \(String(describing: authState!.lastTokenResponse?.accessToken))")
                fulfill(authState!)
            })
        })
    }

    public init(api: Api, endpointClosure: @escaping EndpointClosure = MoyaProvider.defaultEndpointMapping,
                stubClosure: @escaping StubClosure = MoyaProvider.neverStub,
                callbackQueue: DispatchQueue? = nil,
                manager: Manager = MoyaProvider<Target>.defaultAlamofireManager(),
                plugins: [PluginType] = [],
                trackInflights: Bool = false) {
//    public init(api: Api, endpointClosure: @escaping EndpointClosure = MoyaProvider.defaultEndpointMapping,
//                requestClosure: @escaping RequestClosure = MoyaProvider.defaultRequestMapping,
//                stubClosure: @escaping StubClosure = MoyaProvider.neverStub,
//                manager: Manager = MoyaProvider<DynamicInstanceService>.defaultAlamofireManager(),
//                plugins: [PluginType] = [],
//                trackInflights: Bool = false) {
        self.api = api
        self.credentialStorePlugin = CredentialStorePlugin()

        var plugins = plugins
        plugins.append(self.credentialStorePlugin)

        self.authConfig = OIDServiceConfiguration(authorizationEndpoint: URL(string: api.authorizationEndpoint!)!, tokenEndpoint: URL(string: api.tokenEndpoint!)!)
        super.init(endpointClosure: endpointClosure, stubClosure: stubClosure, manager: manager, plugins: plugins, trackInflights: trackInflights)

    }

    public func request(apiService: ApiService,
                        queue: DispatchQueue? = nil,
                        progress: Moya.ProgressBlock? = nil) -> Promise<Moya.Response> {
        return Promise<Any>(resolvers: { fulfill, reject in
            if let authState = self.api.authState {
                authState.performAction(freshTokens: { (accessToken, _, error) in
                    if let error = error {
                        reject(error)
                        return
                    }

                    self.credentialStorePlugin.accessToken = accessToken
                    fulfill(())
                })
            } else {
                reject(ApiServiceError.noAuthState)
            }

        }).then {_ in
            return self.request(target: DynamicApiService(baseURL: URL(string: self.api.apiBaseUri!)!, apiService: apiService))
        }
    }
}

extension DynamicApiProvider: Hashable {
    static func == (lhs: DynamicApiProvider, rhs: DynamicApiProvider) -> Bool {
        return lhs.api.apiBaseUri == rhs.api.apiBaseUri
    }

    var hashValue: Int {
        return api.apiBaseUri?.hashValue ?? 0
    }
}
