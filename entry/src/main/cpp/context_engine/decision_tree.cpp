/**
 * decision_tree.cpp — 自动编译决策树
 *
 * 将 flat rules 编译为决策树:
 *   1. 统计每个 key 的出现频率
 *   2. 按 cost-aware ordering 选择 split key (便宜的特征优先)
 *   3. 递归构建子树
 *
 * Cost ordering (cheap → expensive):
 *   timeOfDay, dayOfWeek, isWeekend < motionState < batteryLevel < geofence < location
 */
#include "context_engine.h"
#include <algorithm>
#include <unordered_set>

namespace context_engine {

// Feature cost: lower = cheaper to evaluate (prefer splitting on cheap features first)
static int featureCost(const std::string& key) {
    // Time features: pure computation, zero cost
    if (key == "timeOfDay" || key == "dayOfWeek" || key == "isWeekend" ||
        key == "hour" || key == "minute") return 0;
    // Device state: already available
    if (key == "batteryLevel" || key == "isCharging" || key == "networkType") return 1;
    // Motion: sensor, low power
    if (key == "motionState" || key == "stepCount") return 2;
    // Location: GPS, higher power
    if (key == "geofence" || key == "location" || key == "latitude" || key == "longitude") return 3;
    // Unknown features: medium cost
    return 2;
}

/** Pick the best split key for a set of rules.
 *  Heuristic: maximize coverage (rules using this key) ÷ cost */
static std::string pickSplitKey(const std::vector<Rule>& rules,
                                 const std::vector<int>& indices,
                                 const std::unordered_set<std::string>& usedKeys) {
    std::unordered_map<std::string, int> keyCount;
    for (int idx : indices) {
        for (const auto& cond : rules[idx].conditions) {
            if (usedKeys.count(cond.key) == 0) {
                keyCount[cond.key]++;
            }
        }
    }

    if (keyCount.empty()) return "";

    std::string bestKey;
    double bestScore = -1.0;
    for (const auto& [key, count] : keyCount) {
        // Score = coverage / (1 + cost)
        double score = static_cast<double>(count) / (1.0 + featureCost(key));
        if (score > bestScore) {
            bestScore = score;
            bestKey = key;
        }
    }
    return bestKey;
}

void RuleEngine::compileTree() {
    tree_.clear();
    if (rules_.empty()) return;

    // All rule indices
    std::vector<int> allIndices;
    allIndices.reserve(rules_.size());
    for (int i = 0; i < static_cast<int>(rules_.size()); i++) {
        if (rules_[i].enabled) {
            allIndices.push_back(i);
        }
    }

    if (allIndices.empty()) return;

    // Recursive tree building (cleaner than iterative with correct indexing)
    struct BuildContext {
        const std::vector<Rule>& rules;
        std::vector<TreeNode>& tree;

        int build(const std::vector<int>& indices, std::unordered_set<std::string> usedKeys) {
            int nodeIdx = static_cast<int>(tree.size());
            tree.push_back(TreeNode{});

            // Find best split key
            std::string splitKey = pickSplitKey(rules, indices, usedKeys);

            // Leaf if: no good split, or few rules, or max depth reached
            if (splitKey.empty() || indices.size() <= 2 || usedKeys.size() >= 5) {
                tree[nodeIdx].splitKey = "";
                tree[nodeIdx].defaultChild = -1;
                tree[nodeIdx].ruleIndices = indices;
                return nodeIdx;
            }

            // Internal node: group rules by their condition value for splitKey
            tree[nodeIdx].splitKey = splitKey;

            std::unordered_map<std::string, std::vector<int>> groups;
            std::vector<int> noCondition;  // rules that don't use this key

            for (int idx : indices) {
                bool found = false;
                for (const auto& cond : rules[idx].conditions) {
                    if (cond.key == splitKey && cond.op == "eq") {
                        groups[cond.value].push_back(idx);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    noCondition.push_back(idx);
                }
            }

            auto childUsedKeys = usedKeys;
            childUsedKeys.insert(splitKey);

            // Build child nodes for each branch value
            // Note: we must build children AFTER this node is fully set up
            std::vector<std::pair<std::string, std::vector<int>>> branches;
            for (auto& [value, ruleIdxs] : groups) {
                // Add noCondition rules to every branch (they match regardless)
                for (int nc : noCondition) ruleIdxs.push_back(nc);
                branches.emplace_back(value, std::move(ruleIdxs));
            }

            // Now build children (tree may grow, so indices are correct)
            for (auto& [value, ruleIdxs] : branches) {
                int childIdx = build(ruleIdxs, childUsedKeys);
                tree[nodeIdx].branches.emplace_back(value, childIdx);
            }

            // Default branch for values not seen in any rule
            if (!noCondition.empty()) {
                int defaultIdx = build(noCondition, childUsedKeys);
                tree[nodeIdx].defaultChild = defaultIdx;
            } else {
                tree[nodeIdx].defaultChild = -1;
            }

            return nodeIdx;
        }
    };

    BuildContext ctx{rules_, tree_};
    ctx.build(allIndices, {});
}

}  // namespace context_engine
