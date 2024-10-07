//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 28/04/2022.
//

import Foundation
@testable import WorkflowEngine


//TODO : this class was copied from the InMemoryFileDataStore.
// Once datastore becomes a separate swift package, the original class should be used.
class TestFlowStateStore: StateStore {
    func saveState<C>(state: C?, fileName: String?) where C : Decodable, C : Encodable {
       saveModel(state, fileName: fileName)
    }
    func loadState<C>(fileName: String?) -> C? where C : Decodable, C : Encodable {
        return loadModel(fileName: fileName)
    }

    // FROM HERE, THIS IS COPIED FROM InMemoryFileDataStore
    var rootPath: URL = URL(fileURLWithPath: "/test")
   

    func modelArchivePath<T>(_ t: T.Type, fileName: String?) -> URL {
        let fileName = fileName ?? String(describing: t).asAcceptableFileName()
        return dataKey(forFilename: fileName).originalURL
    }

    func dataKey(forFilename fileName: String) -> (originalURL: URL, key: String) {
        let url = rootPath.appendingPathComponent(fileName)
        return (url, url.path)
    }
    var data = [String: Data]()
    // FileManager functions are thread safe. We need to encapsulate access to "data"
    // to make it thread-safe as well

    let dataAccessQueue = DispatchQueue(label: "inmemory_data_access."+UUID().uuidString,
                                        qos: .userInteractive)

    //Callback used to observer model save
    var saveModelObserver: ((_ modelName: String, _ fileName: String?) -> Void)?

    func saveModel(rawData: Data, fileName: String) {
        dataAccessQueue.sync {
            let path = modelArchivePath(Data.self, fileName: fileName)
            data[path.path] = rawData
        }
    }

    func saveModel<T>(_ model: T?, fileName: String? = nil) where T: Encodable {
        dataAccessQueue.sync {
            saveModelObserver?(String(describing: T.self), fileName)
            let path = modelArchivePath(T.self, fileName: fileName)

            if let model = model {
                do {
                    data[path.path] = try JSONEncoder().encode(model)
                } catch {
                    print("error: \(error)")
                    data[path.path] = nil
                }
            } else {
                data[path.path] = nil
            }
        }
    }

    func loadModel<T>(fileName: String? = nil) -> T? where T: Decodable {
        return dataAccessQueue.sync {
            let path = modelArchivePath(T.self, fileName: fileName)
            guard let modelData = data[path.path] else {
                return nil
            }
            do {
                return try JSONDecoder().decode(T.self, from: modelData)
            } catch {
                print("error : \(error)")
                return nil
            }
        }
    }

    func write(data: Data?, to url: URL) throws {
        if let data = data {
            self.data[url.path] = data
        } else {
            self.data[url.path] = nil
        }
    }
    func read(from url: URL) -> Data? {
        return data[url.path]
    }

    func listModelFiles() -> [String] {
        return dataAccessQueue.sync { () -> [String] in
            return Array(data.keys.map {
                URL(fileURLWithPath: $0).lastPathComponent
            })
        }
    }
    
    func listModelFileURLs() -> [URL] {
        return dataAccessQueue.sync { () -> [URL] in
            return Array(data.keys.map {
                URL(fileURLWithPath: $0)
            })
        }
    }
}
