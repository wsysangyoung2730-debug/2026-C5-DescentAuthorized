import Foundation

struct GlyphEvaluator: Sendable {
    let maximumMana: Double

    init(maximumMana: Double = 100) {
        self.maximumMana = maximumMana
    }

    func evaluate(
        spell: SpellDefinition,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod,
        erasureZones: [ErasureZone] = []
    ) -> CastingEvaluation {
        guard !strokes.isEmpty, strokes.allSatisfy({ !$0.points.isEmpty }) else {
            return rejected(.noInput, spell: spell)
        }

        guard strokes.count == spell.requiredStrokes else {
            return rejected(.wrongStrokeCount, spell: spell)
        }

        let estimate = GlyphManaEstimator().estimate(
            spell: spell,
            strokes: strokes,
            erasureZones: erasureZones
        )
        let mana = (total: estimate.total, inZones: estimate.inErasureZones)
        let inputProfile = DrawingInputPolicy.evaluationProfile(for: inputMethod)
        var passedRequiredNodes = 0
        var totalRequiredNodes = 0
        var nodeScores = [Double]()
        var pathScores = [Double]()
        var structureScores = [Double]()
        var gradeCap: CastingGrade?

        for (index, stroke) in strokes.enumerated() {
            let spec = spell.glyph.strokes[index]
            let nodeRadius = spec.nodeRadius * inputProfile.nodeRadiusMultiplier

            guard let first = stroke.points.first,
                  first.distance(to: spec.start) <= nodeRadius else {
                return rejected(
                    .invalidStart,
                    spell: spell,
                    mana: mana,
                    passedNodes: passedRequiredNodes,
                    requiredNodes: totalRequiredNodes + spec.requiredNodes.count
                )
            }

            let nodeResult = evaluateNodes(
                spec.requiredNodes,
                in: stroke.points,
                radius: nodeRadius
            )
            passedRequiredNodes += nodeResult.passed
            totalRequiredNodes += spec.requiredNodes.count

            guard nodeResult.passed == spec.requiredNodes.count else {
                return rejected(
                    .missingRequiredNode,
                    spell: spell,
                    mana: mana,
                    passedNodes: passedRequiredNodes,
                    requiredNodes: totalRequiredNodes
                )
            }

            let optionalResult = evaluateNodes(
                spec.optionalNodes,
                in: stroke.points,
                radius: nodeRadius
            )
            if optionalResult.passed < spec.optionalNodes.count,
               let cap = spec.optionalNodeGradeCap {
                gradeCap = min(gradeCap ?? cap, cap)
            }

            nodeScores.append(nodeResult.score)
            pathScores.append(pathScore(
                stroke.points,
                reference: spec.referencePath,
                radius: spec.pathRadius * inputProfile.pathRadiusMultiplier
            ))

            guard let last = stroke.points.last else {
                return rejected(.incompleteGlyph, spell: spell, mana: mana)
            }
            let endDistance = last.distance(to: spec.end)
            guard endDistance <= nodeRadius * 2 else {
                return rejected(
                    .invalidEnd,
                    spell: spell,
                    mana: mana,
                    passedNodes: passedRequiredNodes,
                    requiredNodes: totalRequiredNodes
                )
            }

            let startScore = proximityScore(first.distance(to: spec.start), radius: nodeRadius)
            let endScore = proximityScore(endDistance, radius: nodeRadius)
            structureScores.append((startScore + endScore) / 2)
        }

        for crossing in spell.glyph.crossings {
            guard crossing.firstStrokeIndex < strokes.count,
                  crossing.secondStrokeIndex < strokes.count else {
                return rejected(.missingCrossing, spell: spell, mana: mana)
            }

            let firstDistance = GlyphGeometry.distance(
                from: crossing.center,
                toPolyline: strokes[crossing.firstStrokeIndex].points
            )
            let secondDistance = GlyphGeometry.distance(
                from: crossing.center,
                toPolyline: strokes[crossing.secondStrokeIndex].points
            )
            let crossingRadius = crossing.radius * inputProfile.crossingRadiusMultiplier
            guard firstDistance <= crossingRadius, secondDistance <= crossingRadius else {
                return rejected(
                    .missingCrossing,
                    spell: spell,
                    mana: mana,
                    passedNodes: passedRequiredNodes,
                    requiredNodes: totalRequiredNodes
                )
            }
            structureScores.append(
                (proximityScore(firstDistance, radius: crossingRadius)
                    + proximityScore(secondDistance, radius: crossingRadius)) / 2
            )
        }

        guard mana.total <= maximumMana else {
            return rejected(
                .manaDepleted,
                spell: spell,
                mana: mana,
                passedNodes: passedRequiredNodes,
                requiredNodes: totalRequiredNodes
            )
        }

        let nodes = average(nodeScores)
        let path = average(pathScores)
        let structure = average(structureScores)
        let manaEfficiency = manaEfficiencyScore(used: mana.total, recommended: spell.recommendedMana)
        let score = nodes * 0.4 + path * 0.35 + structure * 0.15 + manaEfficiency * 0.1
        var grade = grade(for: score)
        if let gradeCap, grade > gradeCap {
            grade = gradeCap
        }

        guard grade != .rejected else {
            return rejected(
                .incompleteGlyph,
                spell: spell,
                mana: mana,
                passedNodes: passedRequiredNodes,
                requiredNodes: totalRequiredNodes,
                breakdown: CastingScoreBreakdown(
                    nodes: nodes,
                    path: path,
                    structure: structure,
                    manaEfficiency: manaEfficiency
                )
            )
        }

        return CastingEvaluation(
            score: score,
            grade: grade,
            failure: nil,
            manaUsed: mana.total,
            manaUsedInErasureZones: mana.inZones,
            passedRequiredNodeCount: passedRequiredNodes,
            requiredNodeCount: totalRequiredNodes,
            breakdown: CastingScoreBreakdown(
                nodes: nodes,
                path: path,
                structure: structure,
                manaEfficiency: manaEfficiency
            )
        )
    }

    private func evaluateNodes(
        _ nodes: [NormalizedPoint],
        in points: [NormalizedPoint],
        radius: Double
    ) -> (passed: Int, score: Double) {
        guard !nodes.isEmpty else { return (0, 100) }

        let samples = GlyphGeometry.resample(points)
        var searchStart = 0
        var proximityScores = [Double]()

        for node in nodes {
            guard searchStart < samples.count else { break }

            var bestIndex: Int?
            var bestDistance = Double.infinity
            var enteredRadius = false
            for index in searchStart..<samples.count {
                let distance = samples[index].distance(to: node)
                if distance <= radius {
                    enteredRadius = true
                }
                if enteredRadius, distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
                if enteredRadius, distance > radius {
                    break
                }
            }

            guard let index = bestIndex, bestDistance <= radius else { break }
            proximityScores.append(proximityScore(bestDistance, radius: radius))
            searchStart = index + 1
        }

        let passed = proximityScores.count
        let completion = Double(passed) / Double(nodes.count)
        return (passed, average(proximityScores) * completion)
    }

    private func pathScore(
        _ points: [NormalizedPoint],
        reference: [NormalizedPoint],
        radius: Double
    ) -> Double {
        let samples = GlyphGeometry.resample(points)
        guard !samples.isEmpty else { return 0 }

        let scores = samples.map {
            proximityScore(GlyphGeometry.distance(from: $0, toPolyline: reference), radius: radius)
        }
        return average(scores)
    }

    private func proximityScore(_ distance: Double, radius: Double) -> Double {
        max(0, 100 * (1 - distance / (radius * 2)))
    }

    private func manaEfficiencyScore(used: Double, recommended: Double) -> Double {
        guard recommended > 0 else { return 0 }
        guard used > recommended else { return 100 }
        return max(0, 100 - ((used / recommended) - 1) * 100)
    }

    private func grade(for score: Double) -> CastingGrade {
        switch score {
        case 95...: .perfect
        case 85..<95: .precise
        case 70..<85: .approved
        case 50..<70: .incomplete
        default: .rejected
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 100 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func rejected(
        _ failure: CastingFailure,
        spell: SpellDefinition,
        mana: (total: Double, inZones: Double) = (0, 0),
        passedNodes: Int = 0,
        requiredNodes: Int? = nil,
        breakdown: CastingScoreBreakdown = CastingScoreBreakdown(
            nodes: 0,
            path: 0,
            structure: 0,
            manaEfficiency: 0
        )
    ) -> CastingEvaluation {
        CastingEvaluation(
            score: 0,
            grade: .rejected,
            failure: failure,
            manaUsed: mana.total,
            manaUsedInErasureZones: mana.inZones,
            passedRequiredNodeCount: passedNodes,
            requiredNodeCount: requiredNodes ?? spell.glyph.strokes.reduce(0) { $0 + $1.requiredNodes.count },
            breakdown: breakdown
        )
    }
}
