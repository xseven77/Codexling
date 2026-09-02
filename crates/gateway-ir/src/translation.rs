use serde::{Deserialize, Serialize};

/// High-level fidelity rating for a protocol/provider translation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Fidelity {
    /// Zero loss of semantic intent or provider-specific capability.
    #[default]
    Native,
    /// Compatible execution: minor non-critical emulation without compromising tools or state.
    Compatible,
    /// Degraded execution: at least one feature dropped or textified (must be explicitly allowed).
    Degraded,
    /// Cannot safely execute the agent loop; must reject.
    Unsupported,
}

/// Severity rating for a translation loss item.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LossImpact {
    Cosmetic,
    Minor,
    Critical,
}

/// Details of a specific parameter, header or block lost or emulated during translation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TranslationLoss {
    pub field: String,
    pub reason: String,
    pub impact: LossImpact,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_value: Option<serde_json::Value>,
}

impl TranslationLoss {
    pub fn new(field: impl Into<String>, reason: impl Into<String>, impact: LossImpact) -> Self {
        Self {
            field: field.into(),
            reason: reason.into(),
            impact,
            source_value: None,
        }
    }

    pub fn with_source_value(mut self, value: serde_json::Value) -> Self {
        self.source_value = Some(value);
        self
    }
}

/// Non-fatal compatibility warning reported back in response headers or telemetry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityWarning {
    pub code: String,
    pub message: String,
}

impl CompatibilityWarning {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

/// Container wrapping translated data alongside its fidelity and loss audit log.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TranslationResult<T> {
    pub value: T,
    pub fidelity: Fidelity,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub losses: Vec<TranslationLoss>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warnings: Vec<CompatibilityWarning>,
}

impl<T> TranslationResult<T> {
    pub fn native(value: T) -> Self {
        Self {
            value,
            fidelity: Fidelity::Native,
            losses: Vec::new(),
            warnings: Vec::new(),
        }
    }

    pub fn compatible(value: T, warnings: Vec<CompatibilityWarning>) -> Self {
        Self {
            value,
            fidelity: Fidelity::Compatible,
            losses: Vec::new(),
            warnings,
        }
    }

    pub fn degraded(value: T, losses: Vec<TranslationLoss>, warnings: Vec<CompatibilityWarning>) -> Self {
        Self {
            value,
            fidelity: Fidelity::Degraded,
            losses,
            warnings,
        }
    }

    pub fn add_loss(&mut self, loss: TranslationLoss) {
        if loss.impact == LossImpact::Critical && self.fidelity < Fidelity::Degraded {
            self.fidelity = Fidelity::Degraded;
        } else if loss.impact == LossImpact::Minor && self.fidelity == Fidelity::Native {
            self.fidelity = Fidelity::Compatible;
        }
        self.losses.push(loss);
    }

    pub fn add_warning(&mut self, warning: CompatibilityWarning) {
        self.warnings.push(warning);
    }
}
