//
//  NetworkFetching.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Generic http error
enum APIError: Error {
    case badResponse
}

/// Authentication for specific provider
enum AuthFor {
    case none
    case tmdb
    case bearer(String)

    fileprivate func apply(to request: inout URLRequest) {
        switch self {
        case .none:
            break
        case .tmdb:
            request.setValue("Bearer \(TMDBConfig.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL, auth: AuthFor) async throws -> T {
    var request = URLRequest(url: url)
    auth.apply(to: &request)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw APIError.badResponse
    }
    return try JSONDecoder().decode(T.self, from: data)
}

func postJSON<Body: Encodable, Response: Decodable>(
    _ responseType: Response.Type,
    to url: URL,
    body: Body,
    auth: AuthFor
) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    auth.apply(to: &request)
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw APIError.badResponse
    }
    return try JSONDecoder().decode(Response.self, from: data)
}

/// Sends a request with no response decoding (DELETE / PUT with ignored body).
@discardableResult
func sendRequest(method: String, to url: URL, auth: AuthFor) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    auth.apply(to: &request)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw APIError.badResponse
    }
    return data
}

/// Sends a request with a JSON body and ignores the response body.
@discardableResult
func sendJSON<Body: Encodable>(method: String, to url: URL, body: Body, auth: AuthFor) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    auth.apply(to: &request)
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw APIError.badResponse
    }
    return data
}

/// The signed-in user's backend credentials, read from the keychain (the same
/// keys SessionManager persists). Nil when signed out.
enum CelesteSession {
    static var credentials: (userId: String, token: String)? {
        guard let userId = KeychainStore.get(forKey: "celeste_user_id"),
              let token = KeychainStore.get(forKey: "celeste_session_token") else {
            return nil
        }
        return (userId, token)
    }
}

/// Wrapper for http calls + json decode
func fetchPage<T: Decodable>(_ type: T.Type, from url: URL, auth: AuthFor) async throws -> [T] {
    try await fetchJSON(PagedResponse<T>.self, from: url, auth: auth).results
}

func fetchPagedResponse<T: Decodable>(_ type: T.Type, from url: URL, auth: AuthFor) async throws -> PagedResponse<T> {
    try await fetchJSON(PagedResponse<T>.self, from: url, auth: auth)
}
