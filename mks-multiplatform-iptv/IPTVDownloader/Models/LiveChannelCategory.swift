// LiveChannelsProperties.swift
// Basado en Category.swift para mks-iptv-downloader
// Convertido a Swift por Deymos

import Foundation

struct LiveChannelCategory: Identifiable, Codable, Equatable {
    let categoryId: String
    let categoryName: String
    let parentId: Int
    
    var id: String { categoryId }
    
    static func == (lhs: LiveChannelCategory, rhs: LiveChannelCategory) -> Bool {
        lhs.categoryId == rhs.categoryId
    }
    
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
        
        // Diccionario estático para almacenar las categorías y permitir búsquedas rápidas
        public static var categories: [String: LiveChannelCategory] = [:]
        
        // Método estático para inicializar las categorías desde un array de LiveChannelCategory
        static func loadCategories(_ categoriesArray: [LiveChannelCategory]) {
            categories = Dictionary(uniqueKeysWithValues: categoriesArray.map { ($0.categoryId, $0) })
        }
        
        // Método estático para obtener el nombre de la categoría por su ID
        static func getCategoryNameByID(_ id: String) -> String? {
            return categories[id]?.categoryName
        }
    }
    //
    //// Ejemplo de inicialización
    //let exampleCategory = LiveChannelCategory(categoryId: "102", categoryName: "01 GENERALISTAS", parentId: 0)
    //LiveChannelCategory.loadCategories([exampleCategory])
    //print(LiveChannelCategory.getCategoryNameByID("102") ?? "No se encontró la categoría") // Salida: "01 GENERALISTAS"
}
