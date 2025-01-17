//
//  MovieController.swift
//  MyMovies
//
//  Created by Spencer Curtis on 8/17/18.
//  Copyright © 2018 Lambda School. All rights reserved.
//

import Foundation
import CoreData

enum HTTPMethod: String {
    
    case get = "GET" // read only
    case put = "PUT" // create data
    case post = "POST" // update or replace data
    case delete = "DELETE" // delete data
    
}

class MovieController {
    
    // MARK: - Properties
    
    var searchedMovies: [MovieRepresentation] = []
    
    private let apiKey = "4cc920dab8b729a619647ccc4d191d5e"
    private let baseURL = URL(string: "https://api.themoviedb.org/3/search/movie")!
    
    private let base = URL(string: "https://mymoviesprint.firebaseio.com/")!
    
    func searchForMovie(with searchTerm: String, completion: @escaping (Error?) -> Void) {
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        
        let queryParameters = ["query": searchTerm,
                               "api_key": apiKey]
        
        components?.queryItems = queryParameters.map({URLQueryItem(name: $0.key, value: $0.value)})
        
        guard let requestURL = components?.url else {
            completion(NSError())
            return
        }
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            
            if let error = error {
                NSLog("Error searching for movie with search term \(searchTerm): \(error)")
                completion(error)
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from data task")
                completion(NSError())
                return
            }
            
            do {
                let movieRepresentations = try JSONDecoder().decode(MovieRepresentations.self, from: data).results
                self.searchedMovies = movieRepresentations
                completion(nil)
            } catch {
                NSLog("Error decoding JSON data: \(error)")
                completion(error)
            }
        }.resume()
    }
    
    func put(moive: Movie, completion: @escaping () -> Void = { }) {
        
        let base = URL(string: "https://mymoviesprint.firebaseio.com/")!
        
        let identifier = moive.identifier ?? UUID().uuidString
        moive.identifier = identifier
        
        let requestURL = base
            .appendingPathComponent(identifier)
            .appendingPathExtension("json")
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.put.rawValue
        
        guard let movieRepresentation = moive.movieRepresentation else {
            NSLog("Task Representation is nil")
            completion()
            return
        }
        
        do {
            request.httpBody = try JSONEncoder().encode(movieRepresentation)
        } catch {
            NSLog("Error encoding task representation: \(error)")
            completion()
            return
        }
        
        URLSession.shared.dataTask(with: request) { (_, _, error) in
            
            if let error = error {
                NSLog("Error PUTting task: \(error)")
                completion()
                return
            }
            
            completion()
            }.resume()
    }

    func updateMovie(with representations: [MovieRepresentation]) {
        
        
        let identifiersToFetch = representations.compactMap({ $0.identifier?.uuidString })
        
        // [UUID: TaskRepresentation]
        
        let representationsByID = Dictionary(uniqueKeysWithValues: zip(identifiersToFetch, representations))
        
        // Make a mutable copy of the dictionary above
        var tasksToCreate = representationsByID
        
        let context = CoreDataStack.shared.backgroundContext
        
        context.performAndWait {
            
            do {
                
                
                let fetchRequest: NSFetchRequest<Movie> = Movie.fetchRequest()
                
                // identifier == \(identifier)
                fetchRequest.predicate = NSPredicate(format: "identifier IN %@", identifiersToFetch)
                
                // Which of these tasks exist in Core Data already?
                let existingTasks = try context.fetch(fetchRequest)
                
                // Which need to be updated? Which need to be put into Core Data?
                for movie in existingTasks {
                    guard let identifier = movie.identifier,
                        // This gets the task representation that corresponds to the task from Core Data
                        let representation = representationsByID[identifier] else { continue }
                    
                    movie.title = representation.title
                    movie.identifier = representation.identifier?.uuidString
                    movie.hasWatched = representation.hasWatched!
                    
                    tasksToCreate.removeValue(forKey: identifier)
                }
                
                // Take the tasks that AREN'T in Core Data and create new ones for them.
                for representation in tasksToCreate.values {
                    Movie(representation, context: context)
                }
                
                CoreDataStack.shared.save(context: context)
                
            } catch {
                NSLog("Error fetching tasks from persistent store: \(error)")
            }
        }
    }
    
    func deleteEntryFromServer(movie: Movie, completion: @escaping (Error?) -> Void ) {
        
        guard let identifier = movie.identifier else {return}
        
        let requestURL = base
            .appendingPathComponent(identifier)
            .appendingPathExtension("json")
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.delete.rawValue
        
        URLSession.shared.dataTask(with: request) { (_, _, error) in
            if let error = error {
                NSLog("Error deleting task: \(error)")
                completion(error)
            }
            }.resume()
    }
    
    func createMovie(with title: String) {
        
        let movie = Movie(title: title)
        CoreDataStack.shared.save()
        put(moive: movie!)
        
    }
    
    func updateMovie(movie: Movie, hasWatched: Bool) {
       
        movie.hasWatched = hasWatched
        
        CoreDataStack.shared.save()
        put(moive: movie)
    }
    
    func delete(movie: Movie){
        
        let context = CoreDataStack.shared.mainContext
        
        context.performAndWait {
            deleteEntryFromServer(movie: movie) { (error) in
                NSLog("Error deleting journal")
            }
            context.delete(movie)
            CoreDataStack.shared.save()
            
        }
    }
}
   

