import Combine
import Foundation

final class DisplayName: ObservableObject {
	static let names = [
		"Idiot Operator",
		"If Only",
		"Imperial Order",
		"Independent Observations",
		"Index Origin",
		"Indian Orchard",
		"Individually Optimum",
		"Inexperienced Operator",
		"Infinitely Often",
		"Information Output",
		"Information Overload",
		"Inside Out",
		"Insignificant Other",
		"Integrated Optics",
		"Intelligence Oversight",
		"Internal Order",
		"Internal Organ",
		"International Organization",
		"Inventory Objective",
	]

	@Published private(set) var current: String = "io"

	func roll() {
		let pool = Self.names.filter { $0 != current }
		current = pool.randomElement() ?? Self.names.randomElement() ?? "io"
	}
}
