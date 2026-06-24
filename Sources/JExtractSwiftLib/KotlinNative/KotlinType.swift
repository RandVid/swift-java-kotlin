//
//  KotlinType.swift
//  swift-java
//
//  Represents a Kotlin/Native type. Currently only nominal types are supported.
//

/// A Kotlin type as used in Kotlin/Native generated wrappers.
///
/// Only nominal types are supported for now. Generic types carry their
/// resolved type argument (e.g. `.array(.long)`).
package indirect enum KotlinType: Equatable {
  // Signed integers
  case long
  case int
  case short
  case byte
  // Unsigned integers
  case uLong
  case uInt
  case uShort
  case uByte
  // Other primitives
  case boolean
  case float
  case double
  // Reference / special types
  case string
  case unit
  // Generic
  case array(KotlinType)
  // Nullable (Kotlin nullable type `T?`)
  case optional(KotlinType)
}

extension KotlinType: CustomStringConvertible {
  package var description: String {
    switch self {
    case .long:          return "Long"
    case .int:           return "Int"
    case .short:         return "Short"
    case .byte:          return "Byte"
    case .uLong:         return "ULong"
    case .uInt:          return "UInt"
    case .uShort:        return "UShort"
    case .uByte:         return "UByte"
    case .boolean:       return "Boolean"
    case .float:         return "Float"
    case .double:        return "Double"
    case .string:        return "String"
    case .unit:          return "Unit"
    case .array(let el):
      switch el {
      case .uByte: return "UByteArray"
      default:     return "Array<\(el)>"
      }
    case .optional(let inner): return "\(inner)?"
    }
  }
}
