//
// Copyright 2019-2021, Optimizely, Inc. and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

class ProjectConfig {
    
    var project: Project! {
        didSet {
            updateProjectDependentProps()
        }
    }
    let logger = OPTLoggerFactory.getLogger()
    
    // local runtime forcedVariations [UserId: [ExperimentId: VariationId]]
    // NOTE: experiment.forcedVariations use [ExperimentKey: VariationKey] instead of ids
    var whitelistUsers = AtomicProperty(property: [String: [String: String]]())
    
    var experimentKeyMap = [String: Experiment]()
    var experimentIdMap = [String: Experiment]()
    var experimentFeatureMap = [String: [String]]()
    var eventKeyMap = [String: Event]()
    var attributeKeyMap = [String: Attribute]()
    var featureFlagKeyMap = [String: FeatureFlag]()
    var featureFlagKeys = [String]()
    var rolloutIdMap = [String: Rollout]()
    var allExperiments = [Experiment]()
    var flagVariationsMap = [String: [Variation]]()

    // MARK: - Init
    
    init(datafile: Data) throws {
        var project: Project
        do {
            project = try JSONDecoder().decode(Project.self, from: datafile)
        } catch {
            throw OptimizelyError.dataFileInvalid
        }
        
        if !isValidVersion(version: project.version) {
            throw OptimizelyError.dataFileVersionInvalid(project.version)
        }

        defer { self.project = project }  // deferred-init will call "didSet"
        ProjectConfig.observer.update(project: project)
    }
    
    convenience init(datafile: String) throws {
        try self.init(datafile: Data(datafile.utf8))
    }
    
    init() {}
    
    func updateProjectDependentProps() {
        self.allExperiments = project.experiments + project.groups.map { $0.experiments }.flatMap { $0 }
        
        self.experimentKeyMap = {
            var map = [String: Experiment]()
            allExperiments.forEach { exp in
                map[exp.key] = exp
            }
            return map
        }()
        
        self.experimentIdMap = {
            var map = [String: Experiment]()
            allExperiments.forEach { map[$0.id] = $0 }
            return map
        }()
        
        self.experimentFeatureMap = {
            var experimentFeatureMap = [String: [String]]()
            project.featureFlags.forEach { (ff) in
                ff.experimentIds.forEach {
                    if var arr = experimentFeatureMap[$0] {
                        arr.append(ff.id)
                        experimentFeatureMap[$0] = arr
                    } else {
                        experimentFeatureMap[$0] = [ff.id]
                    }
                }
            }
            return experimentFeatureMap
        }()
        
        self.eventKeyMap = {
            var eventKeyMap = [String: Event]()
            project.events.forEach { eventKeyMap[$0.key] = $0 }
            return eventKeyMap
        }()
        
        self.attributeKeyMap = {
            var map = [String: Attribute]()
            project.attributes.forEach { map[$0.key] = $0 }
            return map
        }()
        
        self.featureFlagKeyMap = {
            var map = [String: FeatureFlag]()
            project.featureFlags.forEach { map[$0.key] = $0 }
            return map
        }()
        
        self.featureFlagKeys = {
            return project.featureFlags.map { $0.key }
        }()

        self.rolloutIdMap = {
            var map = [String: Rollout]()
            project.rollouts.forEach { map[$0.id] = $0 }
            return map
        }()
        
        // all variations for each flag
        // - datafile does not contain a separate entity for this.
        // - we collect variations used in each rule (experiment rules and delivery rules)
        
        self.flagVariationsMap = {
            var map = [String: [Variation]]()
            
            project.featureFlags.forEach { flag in
                var variations = [Variation]()
                
                getAllRulesForFlag(flag).forEach { rule in
                    rule.variations.forEach { variation in
                        if variations.filter({ $0.id == variation.id }).first == nil {
                            variations.append(variation)
                        }
                    }
                }
                map[flag.key] = variations
            }
            
            return map
        }()
        
    }
    
    func getAllRulesForFlag(_ flag: FeatureFlag) -> [Experiment] {
        var rules = flag.experimentIds.compactMap { experimentIdMap[$0] }
        let rollout = self.rolloutIdMap[flag.rolloutId]
        rules.append(contentsOf: rollout?.experiments ?? [])
        return rules
    }

}

// MARK: - Project Change Observer

extension ProjectConfig {
    
    struct ProjectObserver {
        var projectId: String? {
            didSet {
                if oldValue != nil, projectId != oldValue {
                    NotificationCenter.default.post(name: .didReceiveOptimizelyProjectIdChange, object: nil)
                }
            }
        }
        
        var revision: String? {
            didSet {
                if oldValue != nil, revision != oldValue {
                    NotificationCenter.default.post(name: .didReceiveOptimizelyRevisionChange, object: nil)
                }
            }
        }
        
        /// update obseverable properties
        ///
        /// - Parameter project: new Project values (pass nil for reset)
        mutating func update(project: Project?) {
            self.projectId = project?.projectId
            self.revision = project?.revision
        }
        
        mutating func reset() {
            self.update(project: nil)
        }
    }
    
    static var observer = ProjectObserver()
    
}

// MARK: - Persistent Data

extension ProjectConfig {
    func whitelistUser(userId: String, experimentId: String, variationId: String) {
        whitelistUsers.performAtomic { whitelist in
            var dict = whitelist[userId] ?? [String: String]()
            dict[experimentId] = variationId
            whitelist[userId] = dict
        }
    }
    
    func removeFromWhitelist(userId: String, experimentId: String) {
        whitelistUsers.performAtomic { whitelist in
            whitelist[userId]?.removeValue(forKey: experimentId)
        }
    }
    
    func getWhitelistedVariationId(userId: String, experimentId: String) -> String? {
        if let dict = whitelistUsers.property?[userId] {
            return dict[experimentId]
        }
        
        logger.d(.userHasNoForcedVariation(userId))
        return nil
    }
    
    func isValidVersion(version: String) -> Bool {
        // old versions (< 4) of datafiles not supported
        return ["4"].contains(version)
    }
}

// MARK: - Project Access

extension ProjectConfig {
    
    /**
     * Get sendFlagDecisions value.
     */
    var sendFlagDecisions: Bool {
        return project.sendFlagDecisions ?? false
    }
    
    /**
     * Get an Experiment object for a key.
     */
    func getExperiment(key: String) -> Experiment? {
        return experimentKeyMap[key]
    }
    
    /**
     * Get an Experiment object for an Id.
     */
    func getExperiment(id: String) -> Experiment? {
        return experimentIdMap[id]
    }
    
    /**
     * Get an experiment Id for the human readable experiment key
     **/
    func getExperimentId(key: String) -> String? {
        return getExperiment(key: key)?.id
    }
    
    /**
     * Get a Group object for an Id.
     */
    func getGroup(id: String) -> Group? {
        return project.groups.filter { $0.id == id }.first
    }
    
    /**
     * Get a Feature Flag object for a key.
     */
    func getFeatureFlag(key: String) -> FeatureFlag? {
        return featureFlagKeyMap[key]
    }
    
    /**
     * Get all Feature Flag objects.
     */
    func getFeatureFlags() -> [FeatureFlag] {
        return project.featureFlags
    }
    
    /**
     * Get a Rollout object for an Id.
     */
    func getRollout(id: String) -> Rollout? {
        return rolloutIdMap[id]
    }
    
    /**
     * Gets an event for a corresponding event key
     */
    func getEvent(key: String) -> Event? {
        return eventKeyMap[key]
    }
    
    /**
     * Gets an event id for a corresponding event key
     */
    func getEventId(key: String) -> String? {
        return getEvent(key: key)?.id
    }
    
    /**
     * Get an attribute for a given key.
     */
    func getAttribute(key: String) -> Attribute? {
        return attributeKeyMap[key]
    }
    
    /**
     * Get an attribute Id for a given key.
     **/
    func getAttributeId(key: String) -> String? {
        return getAttribute(key: key)?.id
    }
    
    /**
     * Get an audience for a given audience id.
     */
    func getAudience(id: String) -> Audience? {
        return project.getAudience(id: id)
    }
    
    /**
     *  Returns true if experiment belongs to any feature, false otherwise.
     */
    func isFeatureExperiment(id: String) -> Bool {
        return !(experimentFeatureMap[id]?.isEmpty ?? true)
    }
        
    /**
     * Get forced variation for a given experiment key and user id.
     */
    func getForcedVariation(experimentKey: String, userId: String) -> DecisionResponse<Variation> {
        let reasons = DecisionReasons()
        
        guard let experiment = getExperiment(key: experimentKey) else {
            return DecisionResponse(result: nil, reasons: reasons)
        }
        
        if let id = getWhitelistedVariationId(userId: userId, experimentId: experiment.id) {
            if let variation = experiment.getVariation(id: id) {
                let info = LogMessage.userHasForcedVariation(userId, experiment.key, variation.key)
                logger.d(info)
                reasons.addInfo(info)

                return DecisionResponse(result: variation, reasons: reasons)
            }
            
            let info = LogMessage.userHasForcedVariationButInvalid(userId, experiment.key)
            logger.d(info)
            reasons.addInfo(info)

            return DecisionResponse(result: nil, reasons: reasons)
        }
        
        logger.d(.userHasNoForcedVariationForExperiment(userId, experiment.key))
        return DecisionResponse(result: nil, reasons: reasons)
    }
    
    /**
     * Set forced variation for a given experiment key and user id according to a given variation key.
     */
    func setForcedVariation(experimentKey: String, userId: String, variationKey: String?) -> Bool {
        guard let experiment = getExperiment(key: experimentKey) else {
            return false
        }
        
        guard var variationKey = variationKey else {
            logger.d(.variationRemovedForUser(userId, experimentKey))
            self.removeFromWhitelist(userId: userId, experimentId: experiment.id)
            return true
        }
        
        // TODO: common function to trim all keys
        variationKey = variationKey.trimmingCharacters(in: NSCharacterSet.whitespaces)
        
        guard !variationKey.isEmpty else {
            logger.e(.variationKeyInvalid(experimentKey, variationKey))
            return false
        }
        
        guard let variation = experiment.getVariation(key: variationKey) else {
            logger.e(.variationKeyInvalid(experimentKey, variationKey))
            return false
        }
        
        self.whitelistUser(userId: userId, experimentId: experiment.id, variationId: variation.id)
        
        logger.d(.userMappedToForcedVariation(userId, experiment.id, variation.id))
        return true
    }
    
}
