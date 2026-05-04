//
//  Category.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 1/11/24.
//

import Foundation

public struct MovieCategory: Identifiable, Codable {
    public let categoryId: String
    public let categoryName: String
    public let parentId: Int

    public var id: String { categoryId }
    
    public enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }

    // Diccionario estático para almacenar las categorías y permitir búsquedas rápidas
    public static var categories: [String: MovieCategory] = [:]
    
    // Método estático para inicializar las categorías desde un array de MovieCategory
    public static func loadCategories(_ categoriesArray: [MovieCategory]) {
        categories = Dictionary(uniqueKeysWithValues: categoriesArray.map { ($0.categoryId, $0) })
    }

    // Método estático para obtener el nombre de la categoría por su ID
    public static func getCategoryNameByID(_ id: String) -> String? {
        return categories[id]?.categoryName
    }
}

public struct SeriesCategory: Identifiable, Codable {
    public let categoryId: String
    public let categoryName: String
    public let parentId: Int

    public var id: String { categoryId }
    
    public enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }

    // Diccionario estático para almacenar las categorías y permitir búsquedas rápidas
    private static var categories: [String: SeriesCategory] = [:]
    
    // Método estático para inicializar las categorías desde un array de SeriesCategory
    public static func loadCategories(_ categoriesArray: [SeriesCategory]) {
        categories = Dictionary(uniqueKeysWithValues: categoriesArray.map { ($0.categoryId, $0) })
    }

    // Método estático para obtener el nombre de la categoría por su ID
    public static func getCategoryNameByID(_ id: String) -> String? {
        return categories[id]?.categoryName
    }
}
