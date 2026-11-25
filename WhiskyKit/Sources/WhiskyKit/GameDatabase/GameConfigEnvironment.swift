//
//  GameConfigEnvironment.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

/// Environment variables an applied game configuration sets for that game's
/// executables in a bottle.
///
/// ``GameConfigApplicator`` writes a variant's environment variables into the
/// settings of the game's programs when it can find them in the bottle. When
/// the game isn't there yet (applied before it was installed), the variables
/// are kept here instead, in ``BottleSettings/gameConfigEnvironments``, and
/// every launch of one of ``executables`` gets them through the
/// ``EnvironmentLayer/gameProfile`` layer. They live in the bottle settings,
/// so reverting the configuration's snapshot removes them with the rest.
public struct GameConfigEnvironment: Codable, Sendable, Equatable, Identifiable {
    /// The ``GameDBEntry`` these variables came from.
    public var entryId: String
    /// The game's display title, for the bottle configuration view.
    public var title: String
    /// The executable file names the variables apply to, matched without
    /// regard to case. Empty means every program launched in the bottle.
    public var executables: [String]
    /// The variables to set.
    public var variables: [String: String]

    public var id: String {
        entryId
    }

    public init(entryId: String, title: String, executables: [String], variables: [String: String]) {
        self.entryId = entryId
        self.title = title
        self.executables = executables
        self.variables = variables
    }

    /// Whether these variables apply to a launch of `executableName`.
    ///
    /// - Parameter executableName: The file name of the executable being launched.
    /// - Returns: `true` when ``executables`` is empty or names it, ignoring case.
    public func applies(toExecutable executableName: String) -> Bool {
        executables.isEmpty
            || executables.contains { $0.caseInsensitiveCompare(executableName) == .orderedSame }
    }
}

extension BottleSettings {
    /// The variables applied game configurations set for a launch of `executableName`.
    ///
    /// When two configurations set the same variable, the one applied later wins.
    ///
    /// - Parameter executableName: The file name of the executable being launched.
    /// - Returns: The merged variables; empty when no configuration applies.
    public func gameConfigEnvironment(forExecutable executableName: String) -> [String: String] {
        var environment: [String: String] = [:]
        for record in gameConfigEnvironments where record.applies(toExecutable: executableName) {
            environment.merge(record.variables) { _, new in new }
        }
        return environment
    }

    /// The game profile a launch of `url` runs with: the scoped variables of
    /// game configurations applied before the game was in the bottle, with
    /// `caller` (a Steam launch plan's profile) winning where both set one.
    public func gameConfigProfile(launching url: URL, caller: [String: String]) -> [String: String] {
        gameConfigEnvironment(forExecutable: url.lastPathComponent).merging(caller) { _, caller in caller }
    }
}

/// The environment variables an applied game configuration wrote into one
/// program's settings, with the values they replaced, so a revert can undo
/// exactly those.
public struct GameConfigProgramEnvironment: Codable, Sendable, Equatable {
    /// The variables the apply set, with the values it set them to.
    public var appliedValues: [String: String]
    /// The value each of those variables had before the apply. Variables the
    /// apply added are absent.
    public var previousValues: [String: String]

    public init(appliedValues: [String: String], previousValues: [String: String]) {
        self.appliedValues = appliedValues
        self.previousValues = previousValues
    }

    /// Records what applying `variables` to a program whose environment is
    /// `environment` replaces.
    public init(applying variables: [String: String], to environment: [String: String]) {
        self.init(
            appliedValues: variables,
            previousValues: environment.filter { variables[$0.key] != nil }
        )
    }

    /// This record combined with `earlier`, the record of an apply not yet reverted.
    ///
    /// A variable `earlier` already recorded keeps its earlier previous value, so a revert
    /// goes back to the program as it was before the first apply; the applied values are
    /// the later ones, which is what the program holds now.
    public func merged(over earlier: GameConfigProgramEnvironment) -> GameConfigProgramEnvironment {
        var previous = earlier.previousValues
        for key in appliedValues.keys where earlier.appliedValues[key] == nil {
            previous[key] = previousValues[key]
        }
        return GameConfigProgramEnvironment(
            appliedValues: earlier.appliedValues.merging(appliedValues) { _, new in new },
            previousValues: previous
        )
    }

    /// `environment` with the applied variables put back as they were.
    ///
    /// A variable whose value has changed since the apply is left alone, so an
    /// edit made after the apply survives the revert.
    ///
    /// - Parameter environment: The program's current environment.
    /// - Returns: The environment to restore.
    public func reverting(_ environment: [String: String]) -> [String: String] {
        var result = environment
        for (key, applied) in appliedValues where result[key] == applied {
            result[key] = previousValues[key]
        }
        return result
    }
}
