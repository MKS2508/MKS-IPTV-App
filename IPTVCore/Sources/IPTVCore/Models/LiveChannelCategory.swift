// LiveChannelsProperties.swift
// Basado en Category.swift para mks-iptv-downloader
// Convertido a Swift por Deymos

import Foundation

public struct LiveChannelCategory: Identifiable, Codable, Equatable {
    public let categoryId: String
    public let categoryName: String
    @CodableStringInt public var parentId: Int

    public var id: String { categoryId }

    /// Manual initializer for Previews and testing
    public init(categoryId: String, categoryName: String, parentId: Int) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self._parentId = CodableStringInt(wrappedValue: parentId)
    }

    public static func == (lhs: LiveChannelCategory, rhs: LiveChannelCategory) -> Bool {
        lhs.categoryId == rhs.categoryId
    }
    
    public enum CodingKeys: String, CodingKey {
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
