rule SentinelSOC_Harmless_Test
{
    meta:
        description = "Harmless SentinelSOC YARA pipeline test"
        purpose = "lab-validation-only"

    strings:
        $marker = "SENTINELSOC_YARA_TEST" ascii

    condition:
        $marker
}
