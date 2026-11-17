use circuit_definitions::snark_wrapper::franklin_crypto::bellman::pairing::bn256::Fr;
use circuit_definitions::snark_wrapper::franklin_crypto::bellman::pairing::ff::{
    Field, PrimeField, PrimeFieldRepr,
};
use handlebars::Handlebars;
use serde_json::json;

use std::collections::HashMap;
use std::error::Error;

use lazy_static::lazy_static;
use serde_json::Value;

use crate::types::{CommitmentSlot, G2Elements};
use crate::utils::{
    convert_list_to_hexadecimal, create_hash_map, format_const, format_mstore, get_modexp_function,
};

lazy_static! {
    static ref COMMITMENTS_SLOTS: HashMap<&'static str, CommitmentSlot> = create_hash_map(&[
        (
            "gate_setup_commitments",
            CommitmentSlot {
                x: "VK_GATE_SETUP_{}_X_SLOT",
                y: "VK_GATE_SETUP_{}_Y_SLOT"
            }
        ),
        (
            "gate_selectors_commitments",
            CommitmentSlot {
                x: "VK_GATE_SELECTORS_{}_X_SLOT",
                y: "VK_GATE_SELECTORS_{}_Y_SLOT"
            }
        ),
        (
            "permutation_commitments",
            CommitmentSlot {
                x: "VK_PERMUTATION_{}_X_SLOT",
                y: "VK_PERMUTATION_{}_Y_SLOT"
            }
        ),
        (
            "lookup_tables_commitments",
            CommitmentSlot {
                x: "VK_LOOKUP_TABLE_{}_X_SLOT",
                y: "VK_LOOKUP_TABLE_{}_Y_SLOT"
            }
        ),
    ]);
    static ref INDIVIDUAL_COMMITMENTS: HashMap<&'static str, CommitmentSlot> = create_hash_map(&[
        (
            "lookup_selector_commitment",
            CommitmentSlot {
                x: "VK_LOOKUP_SELECTOR_X_SLOT",
                y: "VK_LOOKUP_SELECTOR_Y_SLOT"
            }
        ),
        (
            "lookup_table_type_commitment",
            CommitmentSlot {
                x: "VK_LOOKUP_TABLE_TYPE_X_SLOT",
                y: "VK_LOOKUP_TABLE_TYPE_Y_SLOT"
            }
        ),
    ]);
    static ref G2_ELEMENTS: HashMap<&'static str, G2Elements> = create_hash_map(&[(
        "g2_elements",
        G2Elements {
            x1: "G2_ELEMENTS_{}_X1",
            x2: "G2_ELEMENTS_{}_X2",
            y1: "G2_ELEMENTS_{}_Y1",
            y2: "G2_ELEMENTS_{}_Y2",
        }
    ),]);
    static ref NON_RESIDUES: HashMap<&'static str, &'static str> =
        create_hash_map(&[("non_residues", "NON_RESIDUES_{}"),]);
}

pub fn insert_residue_elements_and_commitments(
    template: &str,
    vk: &HashMap<String, Value>,
    vk_hash: &str,
    contract_name: &str,
) -> Result<String, Box<dyn Error>> {
    let (domain_size, domain_size_log, omega) = domain_parameters(vk)?;
    let mut omega_bytes = Vec::new();
    omega.into_repr().write_be(&mut omega_bytes)?;
    let omega_hex = hex::encode(omega_bytes);
    let reg = Handlebars::new();
    let residue_g2_elements = generate_residue_g2_elements(vk);
    let commitments = generate_commitments(vk);

    let verifier_contract_template =
        template.replace("{{residue_g2_elements}}", &residue_g2_elements);

    let modexp_function = get_modexp_function();
    let verifier_contract_template =
        verifier_contract_template.replace("{{modexp_function}}", &modexp_function);

    Ok(reg.render_template(
        &verifier_contract_template,
        &json!({"residue_g2_elements": residue_g2_elements,
                        "commitments": commitments,
                        "vk_hash": vk_hash,
                        "omega": format!("0x{}", omega_hex.trim_start_matches('0')),
                        "domain_size": format!("0x{:x}", domain_size),
                        "domain_size_log": domain_size_log,
                        "contract_name": contract_name}),
    )?)
}

// SYSCOIN: the PLONK key stores n = domain_size - 1. Security100 uses 2^25,
// so the verifier must derive its domain from the key instead of assuming 2^24.
fn domain_parameters(vk: &HashMap<String, Value>) -> Result<(u64, u32, Fr), Box<dyn Error>> {
    let n = vk
        .get("n")
        .and_then(Value::as_u64)
        .ok_or("PLONK VK n must be an unsigned integer")?;
    let domain_size = n.checked_add(1).ok_or("PLONK VK n overflows domain size")?;
    if domain_size < 2 || !domain_size.is_power_of_two() {
        return Err("PLONK VK n + 1 must be a power of two greater than one".into());
    }
    let domain_size_log = domain_size.trailing_zeros();
    if domain_size_log > Fr::S {
        return Err("PLONK VK domain exceeds the scalar field two-adicity".into());
    }
    // Match the pinned native verifier's radix-two domain construction.
    let mut omega = Fr::root_of_unity();
    for _ in domain_size_log..Fr::S {
        omega.square();
    }
    Ok((domain_size, domain_size_log, omega))
}

fn extract_commitment_slots(items: &[Value], slot_tuple: CommitmentSlot) -> String {
    items
        .iter()
        .enumerate()
        .map(|(idx, item)| {
            let map = item.as_object().unwrap();
            let x = map.get("x").unwrap().as_array().unwrap();
            let y = map.get("y").unwrap().as_array().unwrap();
            let x = convert_list_to_hexadecimal(x);
            let mstore_x = format_mstore(&x, &slot_tuple.x.replace("{}", &idx.to_string()));
            let y = convert_list_to_hexadecimal(y);
            let mstore_y = format_mstore(&y, &slot_tuple.y.replace("{}", &idx.to_string()));
            format!("{}{}", mstore_x, mstore_y)
        })
        .collect::<Vec<String>>()
        .join("")
}

fn extract_non_residues(items: &[Value], slot_name: &str) -> String {
    items
        .iter()
        .enumerate()
        .map(|(idx, item)| {
            let hex_value = convert_list_to_hexadecimal(
                item.as_array().expect("Failed to parse item as array"),
            );
            format_const(&hex_value, &slot_name.replace("{}", &idx.to_string()))
        })
        .collect::<Vec<String>>()
        .join("")
}

fn extract_individual_commitments(item: &Value, commitment_slot: CommitmentSlot) -> String {
    let x = convert_list_to_hexadecimal(
        item.get("x")
            .expect("x value not found")
            .as_array()
            .expect("x value not an array"),
    );
    let mut output = format_mstore(&x, commitment_slot.x);

    let y = convert_list_to_hexadecimal(
        item.get("y")
            .expect("y value not found")
            .as_array()
            .expect("y value not an array"),
    );
    output.push_str(&format_mstore(&y, commitment_slot.y));

    output
}

fn extract_g2_elements(elements: &[Value], g2_elements: G2Elements) -> String {
    let slots: [&str; 4] = [
        g2_elements.x1,
        g2_elements.x2,
        g2_elements.y1,
        g2_elements.y2,
    ];
    let xy_pairs = [("x", "c1"), ("x", "c0"), ("y", "c1"), ("y", "c0")];

    elements
        .iter()
        .enumerate()
        .flat_map(|(idx, element)| {
            xy_pairs.iter().enumerate().map(move |(i, &(xy, c))| {
                let field = element
                    .get(xy)
                    .unwrap_or_else(|| panic!("{} value not found", xy))
                    .as_object()
                    .unwrap_or_else(|| panic!("{} value not an object", xy));

                let c_value = convert_list_to_hexadecimal(
                    field
                        .get(c)
                        .unwrap_or_else(|| panic!("{} value not found", c))
                        .as_array()
                        .unwrap_or_else(|| panic!("{} value not an array", c)),
                );
                format_const(&c_value, &slots[i].replace("{}", &idx.to_string()))
            })
        })
        .collect::<Vec<String>>()
        .join("")
}

fn generate_commitments(vk: &HashMap<String, Value>) -> String {
    let commitments_data = [
        ("gate_setup_commitments", "gate setup commitments"),
        ("gate_selectors_commitments", "gate selectors commitments"),
        ("permutation_commitments", "permutation commitments"),
        ("lookup_tables_commitments", "lookup tables commitments"),
    ];

    let individual_commitments_data = [
        ("lookup_selector_commitment", "lookup selector commitment"),
        ("lookup_table_type_commitment", "table type commitment"),
    ];

    let commitments = commitments_data
        .iter()
        .map(|(key, comment)| {
            let data = vk.get(*key).unwrap().as_array().unwrap();
            format!(
                "            // {}\n{}",
                comment,
                extract_commitment_slots(data, COMMITMENTS_SLOTS[*key])
            )
        })
        .collect::<Vec<String>>()
        .join("\n");

    let individual_commitments = individual_commitments_data
        .iter()
        .map(|(key, comment)| {
            format!(
                "\n            // {}\n{}",
                comment,
                extract_individual_commitments(vk.get(*key).unwrap(), INDIVIDUAL_COMMITMENTS[*key])
            )
        })
        .collect::<Vec<String>>()
        .join("");

    format!("{}{}", commitments, individual_commitments)
}

fn generate_residue_g2_elements(vk: &HashMap<String, Value>) -> String {
    let mut residue_g2_elements = String::new();

    let vk_non_residues = vk.get("non_residues").unwrap().as_array().unwrap();
    residue_g2_elements.push_str("// non residues\n");
    residue_g2_elements.push_str(&extract_non_residues(
        vk_non_residues,
        NON_RESIDUES["non_residues"],
    ));

    let vk_g2_elements = vk.get("g2_elements").unwrap().as_array().unwrap();
    residue_g2_elements.push_str("\n    // trusted setup g2 elements\n");
    residue_g2_elements.push_str(&extract_g2_elements(
        vk_g2_elements,
        G2_ELEMENTS["g2_elements"],
    ));

    residue_g2_elements
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(n: Value) -> HashMap<String, Value> {
        HashMap::from([("n".to_string(), n)])
    }

    fn omega_hex(omega: Fr) -> String {
        let mut bytes = Vec::new();
        omega.into_repr().write_be(&mut bytes).unwrap();
        format!("0x{}", hex::encode(bytes).trim_start_matches('0'))
    }

    #[test]
    fn legacy_2p24_domain_is_unchanged() {
        let (size, log, omega) = domain_parameters(&key(json!((1u64 << 24) - 1))).unwrap();
        assert_eq!((size, log), (1 << 24, 24));
        assert_eq!(
            omega_hex(omega),
            "0x1951441010b2b95a6e47a6075066a50a036f5ba978c050f2821df86636c0facb"
        );
        let template = include_str!("../data/plonk_verifier_contract_template.txt");
        let mut vk: HashMap<String, Value> =
            serde_json::from_str(include_str!("../data/ZKsyncOS_plonk_scheduler_key.json"))
                .unwrap();
        vk.insert("n".to_string(), json!((1u64 << 24) - 1));
        let legacy_template = template
            .replace(
                "{{omega}}",
                "0x1951441010b2b95a6e47a6075066a50a036f5ba978c050f2821df86636c0facb",
            )
            .replace("{{domain_size}}", "0x1000000")
            .replace("{{domain_size_log}}", "24");
        assert_eq!(
            insert_residue_elements_and_commitments(template, &vk, "test-hash", "ZKsyncOS")
                .unwrap(),
            insert_residue_elements_and_commitments(&legacy_template, &vk, "test-hash", "ZKsyncOS")
                .unwrap()
        );
    }

    #[test]
    fn security100_2p25_domain_matches_native_field() {
        let (size, log, omega) = domain_parameters(&key(json!((1u64 << 25) - 1))).unwrap();
        assert_eq!((size, log), (1 << 25, 25));
        // Independently: 7^((r-1)/2^25) mod the BN256 scalar field modulus.
        assert_eq!(
            omega_hex(omega),
            "0xd94d63997367c97a8ed16c17adaae39262b9af83acb9e003f94c217303dd160"
        );
        assert_eq!(omega.pow(&[size]), Fr::one());
        assert_ne!(omega.pow(&[size / 2]), Fr::one());
    }

    #[test]
    fn invalid_domain_sizes_are_rejected() {
        for n in [
            json!(0),
            json!(2),
            json!(u64::MAX),
            json!((1u64 << (Fr::S + 1)) - 1),
            json!(-1),
            json!(3.5),
            json!(true),
            json!("16777215"),
            Value::Null,
        ] {
            assert!(
                domain_parameters(&key(n.clone())).is_err(),
                "accepted invalid n: {}",
                n
            );
        }
        assert!(domain_parameters(&HashMap::new()).is_err());
    }

    #[test]
    fn scalar_field_boundary_domain_is_valid() {
        let size = 1u64 << Fr::S;
        let (_, log, omega) = domain_parameters(&key(json!(size - 1))).unwrap();
        assert_eq!(log, Fr::S);
        assert_eq!(omega, Fr::root_of_unity());
        assert_eq!(omega.pow(&[size]), Fr::one());
        assert_ne!(omega.pow(&[size / 2]), Fr::one());
    }
}
