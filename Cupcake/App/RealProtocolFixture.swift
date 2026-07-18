import CupcakeModels
import Foundation
import SwiftData

enum RealProtocolFixture {
    struct Section {
        let name: String
        let stepDescriptions: [String]
        let stepDurations: [Int?]
    }

    static let sections: [Section] = [
        Section(
            name: "Overnight culture",
            stepDescriptions: [
                "<p>Using a <span class=\"component-amount\">200 µL</span>  pipette tip, remove one of the colonies from the plate and drop the tip into <span class=\"component-amount\">300 mL</span>  LB broth medium, supplemented with <span class=\"component-amount\">50 mg/L</span>  kanamycin.</p><p></p>",
                "<p>Incubate at  <span class=\"component-temperature\">37 °C</span>  with  <span class=\"component-centrifuge\">180 rpm,  °C, </span>  -  <span class=\"component-centrifuge\">200 rpm,  °C, </span>  rotational shaking <span class=\"component-duration\">Overnight</span> .</p><figure><div class=\"component-note\"><p>The culture medium should become totally opaque in the morning.</p></div> </figure><figure></figure><figure></figure><figure></figure><figure></figure><p></p>",
            ],
            stepDurations: [
                0,
                14400,
            ]
        ),
        Section(
            name: "Phosphorylation",
            stepDescriptions: [
                "<p></p><figure><div class=\"component-note\"><p>In order to produce <span class=\"component-amount\">1 mg</span>  of phosphorylated Rab10, it is necessary to phosphorylate <span class=\"component-amount\">9.0 mg</span>  -<span class=\"component-amount\">10.0 mg</span>  of purified Rab10 protein and then repurify the phosphorylated species. Hence the Rab10 protein from <span class=\"component-amount\">36 L</span>  of bacterial culture is required and must be prepared first. We combine the Rab10 protein from three <span class=\"component-amount\">12 L</span>  preparations for this purpose.</p><p></p></div> </figure><p>Mix <span class=\"component-amount\">10 mg</span>  (<span class=\"component-amount\">4 mL</span>  of Rab10 protein at <span class=\"component-amount\">2.5 mg</span> ) in SEC buffer I with <span class=\"component-amount\">4.0 mg</span>  of His-MST3 protein (  <span class=\"component-concentration\">3.5 mg/mL</span> ), <span class=\"component-amount\">0.25 mL</span>   <span class=\"component-concentration\">1 Molarity (M)</span>  Tris <span class=\"component-ph\">pH 8.0</span>  ( <span class=\"component-concentration\">50 millimolar (mM)</span>  f.c.), <span class=\"component-amount\">55 µL</span>   <span class=\"component-concentration\">1 Molarity (M)</span>  MgCl<sub>2</sub> (  <span class=\"component-concentration\">10 millimolar (mM)</span>  f.c.), and <span class=\"component-amount\">55 µL</span>   <span class=\"component-concentration\">0.2 Molarity (M)</span>  ATP ( <span class=\"component-concentration\">2 millimolar (mM)</span>  f.c.) and incubate at  <span class=\"component-temperature\">28 °C</span>  for <span class=\"component-duration\">16:00:00</span>  – <span class=\"component-duration\">20:00:00</span> .</p><p></p>",
                "<p></p><figure><div class=\"component-note\"><p>Although MST3 is not a very potent Rab10 kinase, 90% of the Rab protein does become phosphorylated in these conditions.</p></div> </figure><p>After the phosphorylation reaction is completed, remove the kinase by depletion over a <span class=\"component-amount\">1 mL</span>  Ni-agarose bed.</p><figure><div class=\"component-note\"><p>Some losses occur, but <span class=\"component-amount\">8 mg</span>  of phosphorylated Rab10 can be recovered.</p><p></p></div> </figure><p></p><p></p>",
            ],
            stepDurations: [
                129600,
                0,
            ]
        ),
        Section(
            name: "Transformation of plasmid into competent bacteria",
            stepDescriptions: [
                "<p>Mix <span class=\"component-amount\">10 µL</span>  of pET28a 6HIS Thrombin Rab10 1-181 plasmid (around  <span class=\"component-concentration\">50 ng/µl</span> ) with <span class=\"component-amount\">50 µL</span> -<span class=\"component-amount\">100 µL</span>  of the competent BL21(DE3) cells and incubate  <span class=\"component-temperature\">On ice</span>  for <span class=\"component-duration\">00:30:00</span> .</p><p></p>",
                "<p>Transfer the vial to a heat block equilibrated at  <span class=\"component-temperature\">42 °C</span>  and leave for <span class=\"component-duration\">00:00:50</span> .</p><p></p>",
                "<p>Transfer the vial back into ice and add <span class=\"component-amount\">1 mL</span>  SOC medium and mix gently.</p><p></p>",
                "<p>Incubate for <span class=\"component-duration\">04:00:00</span>  at  <span class=\"component-temperature\">37 °C</span>   for recovery.</p><p></p>",
                "<p>Plate <span class=\"component-amount\">0.1 mL</span>  of the transformation onto a LB broth/agar plate supplemented with  <span class=\"component-concentration\">50 µg/ml</span>  kanamycin.</p><p></p>",
                "<p>Leave the plate <span class=\"component-duration\">Overnight</span>  in a  <span class=\"component-temperature\">37 °C</span>  incubator.</p><p></p>",
            ],
            stepDurations: [
                1800,
                50,
                0,
                14400,
                0,
                14400,
            ]
        ),
        Section(
            name: "Quality control",
            stepDescriptions: [
                "<p>Separate <span class=\"component-amount\">3 µg</span>  of the protein on a 4% - 20% Tris Glycine SDS-polyacrylamid gel and stain with Instant Blue (Figure 4a).</p><figure><div class=\"component-note\"><p>The protein should be &gt;95% homogeneous.</p><figure><img class=\"component-image\" src=\"https://content.protocols.io/files/dv3fbixhp.jpg\" alt=\"image.png\" width=\"550\" height=\"377\"> </figure><p></p></div> </figure><p></p><p></p>",
                "<p>Separate a <span class=\"component-amount\">3 µg</span>  of unphosphorylated Rab10 (1-181) and <span class=\"component-amount\">3 µg</span>  of unphosphorylated Rab10 (1-181) on a 12% Phos-tag SDS-Polyacrylamid gel that separates phosphorylated and non-phosphorylated Rab proteins, run as described previously (Ito et al. 2016) (Figure 4b).</p><figure><div class=\"component-note\"><p>The migration of the phosphorylated and non-phosphorylated pRab10 proteins can clearly be distinguished.</p><figure><img class=\"component-image\" src=\"https://content.protocols.io/files/dv3jbixhp.jpg\" alt=\"image.png\" width=\"550\" height=\"377\"> </figure><p></p></div> </figure><p></p>",
            ],
            stepDurations: [
                0,
                0,
            ]
        ),
        Section(
            name: "Preparation of cell lysate and pulldown of His-Rab10 on Ni-agarose",
            stepDescriptions: [
                "<p>Slowly thaw the vials with the cell suspension in cold water.</p>",
                "<p>After thawing chill suspension  <span class=\"component-temperature\">On ice</span>  and then sonicate, using a probe sonicator (Cell disruptor).</p><p></p>",
                "<p>Settings: 6 – 8 pulses of <span class=\"component-duration\">00:00:15</span>  with <span class=\"component-duration\">00:00:15</span>  pauses. Set the amplitude to 50%.</p><p></p>",
                "<p>Transfer the sonicated suspension into <span class=\"component-amount\">50 mL</span>  Beckman polypropylene centrifuge vials and sediment the insoluble material by centrifugation for <span class=\"component-duration\">00:25:00</span>  at  <span class=\"component-centrifuge\">40000 x g,  °C, </span>  an  <span class=\"component-temperature\">4 °C</span>  using a 25.50 or a 30.50 rotor in a Beckman Avanti centrifuge.</p><p></p>",
                "<p>Recover the supernatants by carefully decanting them into a <span class=\"component-amount\">500 mL</span>  Corning PP conical centrifuge tube.</p><p></p>",
                "<p>During the centrifugation step equilibrate <span class=\"component-amount\">3.0 mL</span>  Ni-agarose <span class=\"component-amount\">6 mL</span>  of a 50% slurry, sufficient for a <span class=\"component-amount\">12 L</span>  expression) by washing it three times with Milli Q water and once with cell collection buffer.</p><p></p>",
                "<p>Add a 50% slurry of the washed Ni-agarose in collection buffer to the lysate and incubate the mix on a Roller Mixer for <span class=\"component-duration\">01:30:00</span>  in a cold room set at  <span class=\"component-temperature\">4 °C</span> .</p><p></p>",
                "<p>Avoid excessive agitation and especially formation of foam.</p>",
                "<p>In the meanwhile, prepare and chill the Ni-wash buffer.</p>",
                "<p>Carefully sediment the Ni-agarose by centrifugation using a Beckman J6 with a 4.2 rotor and suitable adaptors.</p>",
                "<p>Centrifuge at  <span class=\"component-centrifuge\">1000 rpm,  °C, </span>  for <span class=\"component-duration\">00:05:00</span>  at  <span class=\"component-temperature\">4 °C</span> .</p><p></p>",
                "<p>Remove the lid and carefully remove the supernatant containing the depleted lysate using a <span class=\"component-amount\">25 mL</span>  pipette, being careful not to disturb the Ni-agarose.</p><p></p>",
                "<p>Add <span class=\"component-amount\">6 mL</span>  of Ni-wash buffer.</p><p></p>",
                "<p>Prepare a <span class=\"component-amount\">1000 µL</span>  pipette tip by removing <span class=\"component-amount\">5 mm</span>  – <span class=\"component-amount\">7 mm</span>  from the pointed end using scissors.</p><figure><div class=\"component-note\"><p> This allows it to be used to facilely resuspend the agarose.</p></div> </figure><p></p><p></p>",
                "<p>Resuspend the Ni-agarose using a P1000 with such a modified blue tip and aliquot the Ni-agarose into a <span class=\"component-amount\">15 mL</span>  centrifuge vial.</p><p></p>",
                "<p>Wash out any remaining agarose from the large vial with <span class=\"component-amount\">1 mL</span>  of Ni-wash buffer and pool with the first batch to maximise recovery.</p><p></p>",
                "<p>Fill the <span class=\"component-amount\">15 mL</span>  vial to the top with Ni-wash buffer, mix well and sediment resin by centrifugation at  <span class=\"component-centrifuge\">1000 x g,  °C, </span>  for <span class=\"component-duration\">00:01:00</span>  using an Eppendorf 5810 R centrifuge.</p><p></p>",
                "<p>Remove the Ni-wash buffer with a thin vacuum line and replace with fresh Ni-wash buffer. Repeat this step 5 times in total to thoroughly wash the resin.</p>",
                "<p>Remove all Ni-wash buffer without disturbing the agarose bed and add <span class=\"component-amount\">1 mL</span>  of Ni-wash buffer.</p><p></p>",
                "<p>Add 100U = <span class=\"component-amount\">100 µL</span>  Thrombin solution (1000 Units per ml) to the Ni-agarose and mix carefully but well.</p><p></p>",
                "<p>Incubate the Ni-agarose with Thrombin for <span class=\"component-duration\">02:00:00</span>  at ambient temperature (  <span class=\"component-temperature\">20 °C</span>  –  <span class=\"component-temperature\">24 °C</span>  ) and mix occasionally.</p><p></p>",
                "<p>Transfer the Ni-agarose into a Biorad <span class=\"component-amount\">5 mL</span>  Polyprep column and let the digested protein drip into a fresh <span class=\"component-amount\">15 mL</span>  vial.</p><p></p>",
                "<p>Wash out the original <span class=\"component-amount\">15 mL</span>  vial with <span class=\"component-amount\">2 mL</span>  Ni-wash buffer and pool with the Ni-agarose in the Polyprep column. This improves recovery.</p><p></p>",
                "<p>Finally, after the Ni-agarose has settled down add another <span class=\"component-amount\">2 mL</span>  of Ni-wash buffer to recover any remaining digested protein.</p><figure><div class=\"component-note\"><p> At this stage there should be <span class=\"component-amount\">5 mL</span>  – <span class=\"component-amount\">6 mL</span>  of a protein solution at  <span class=\"component-concentration\">1 mg/mL</span>  -  <span class=\"component-concentration\">2 mg/mL</span> .</p><p></p></div> </figure><p></p><p></p>",
            ],
            stepDurations: [
                0,
                0,
                30,
                1500,
                0,
                0,
                5400,
                0,
                0,
                0,
                300,
                0,
                0,
                0,
                0,
                0,
                60,
                0,
                0,
                0,
                7200,
                0,
                0,
                0,
            ]
        ),
        Section(
            name: "Chromatography on a Source 15 S HR10/10 column to separate phospho species",
            stepDescriptions: [
                "<p>In order to separate the phospho species from each other and from the remaining unphosphorylated protein, employ cation exchange chromatography using a Source 15 S column.</p>",
                "<p>To this end, pack an empty HR10/10 or GL 10/100 column with <span class=\"component-amount\">10 mL</span>  Source 15 S resin and use vacuum suction to obtain a homogenous well packed resin bed.</p><figure><div class=\"component-note\"><p>Ion exchange chromatography is a concentrating method, hence the load volume is not critical.</p></div> </figure><p></p><p></p>",
                "<p>Therefore, dilute the monomeric Rab10 sample into the Low Salt buffer to reduce the ionic strength sufficiently for the protein to bind.</p>",
                "<p>Equilibrate the Source 15 S HR10/10 with the IEX- buffers using an Äkta Pure or Purifier.</p>",
                "<p>Dilute the pRab10 protein isolated from the gel filtration step tenfold into the IEX-Low Salt buffer.</p>",
                "<p>Apply aliquots equivalent to <span class=\"component-amount\">3 mg</span>  to the S-column at a flowrate of <span class=\"component-amount\">2 ml/min</span> .</p><figure><div class=\"component-note\"><p>Two column runs may be necessary.</p></div> </figure><figure></figure><p></p><p></p>",
                "<p>Develop the column at the same flow rate with a shallow <span class=\"component-amount\">100 mL</span>  gradient to 30% IEX-High Salt buffer collecting <span class=\"component-amount\">1.0 mL</span>  fractions.</p><figure><div class=\"component-note\"><p>Generally, up to four peaks are resolved see Figure 3. The dominant peak eluting at 15 mS/cm (here <span class=\"component-amount\">148 mL</span> ) represents single phosphorylated Rab10.</p><figure><img class=\"component-image\" src=\"https://content.protocols.io/files/dv3bbixhp.jpg\" alt=\"image.png\" width=\"550\" height=\"374\"> </figure><p></p></div> </figure><p></p>",
                "<p>Pool the fractions containing pRab10 protein.</p><figure><div class=\"component-note\"><p> Protein yield should exceed <span class=\"component-amount\">1.0 mg</span> .</p><p></p></div> </figure><p></p>",
                "<p>Supplement GTPgS to  <span class=\"component-concentration\">1 micromolar (µM)</span>  or GDP to  <span class=\"component-concentration\">1 micromolar (µM)</span>  as required.</p><p></p>",
                "<p>Aliquot into convenient batches, freeze in liquid nitrogen and store at  <span class=\"component-temperature\">-70 °C</span> .</p><p></p>",
            ],
            stepDurations: [
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            ]
        ),
        Section(
            name: "Isolation of monomeric Rab10 (1-181) by Size Exclusion Chromatography",
            stepDescriptions: [
                "<p></p><figure><div class=\"component-note\"><p>The recovered, untagged Rab10 is a mix of aggregated Rab10 (MW &gt; 100 kDa), Thrombin (native Mw 37 kDa) and monomeric Rab10 1-181 (Mw 22.9 kDa).</p></div> </figure><p>Equilibrate a Superdex 75 HiPrep (XK 16/60) column in SEC buffer I.</p>",
                "<p>Apply the digested Rab10 sample either in 2 x <span class=\"component-amount\">3 mL</span>  or as 1 x <span class=\"component-amount\">6 mL</span>  to the column and develop the column at a flowrate of <span class=\"component-amount\">1.2 ml/min</span> .</p><figure><div class=\"component-note\"><p>We normally observe a substantial amount of protein eluting at the void volume and thereafter.</p></div> </figure><p></p><p></p>",
                "<p>However, seperate the monomeric Rab10 from these aggregates and contaminants and elutes at around <span class=\"component-amount\">84 mL</span>  (Figure 1). Collect the fractions of this peak.</p><figure><div class=\"component-note\"><p>We normally obtain <span class=\"component-amount\">3.0 mg</span>  – <span class=\"component-amount\">3.8 mg</span>  of monomeric Rab10 from such preparation from <span class=\"component-amount\">12 L</span>  of bacterial culture.</p><figure><img class=\"component-image\" src=\"https://content.protocols.io/files/dv23bixhp.jpg\" alt=\"image.png\" width=\"550\" height=\"359\"> </figure><p></p></div> </figure><p></p><p></p>",
                "<p>Pool and concentrate the protein using Amicon Ultra 3000 Da MWCO filters.</p><figure><div class=\"component-note\"><p>The protein tolerates concentration to  <span class=\"component-concentration\">5.0 mg/mL</span>  and more. It can be frozen in liquid nitrogen and stored at  <span class=\"component-temperature\">-70 °C</span> .</p><p></p></div> </figure><p></p>",
            ],
            stepDurations: [
                0,
                0,
                0,
                0,
            ]
        ),
        Section(
            name: "Collection of cells and preparation of lysate",
            stepDescriptions: [
                "<p>The following morning prepare <span class=\"component-amount\">0.5 L</span>  of cell collection buffer and chill  <span class=\"component-temperature\">On ice</span> .</p><p></p>",
                "<p>Decant the content of the <span class=\"component-amount\">2 L</span>  conical flasks into <span class=\"component-amount\">1 L</span>  Beckman centrifuge pots, close the pots with their screwcap lids and sediment the cells by centrifugation for <span class=\"component-duration\">00:25:00</span>  at  <span class=\"component-temperature\">4 °C</span>  at  <span class=\"component-centrifuge\">4200 rpm,  °C, </span>  using a Beckman J6 centrifuge with the 6 x <span class=\"component-amount\">1 L</span>  rotor (4.2).</p><p></p>",
                "<p>Collect and open the pots and carefully decant the spent supernatant medium back into the flasks.</p><figure><div class=\"component-note\"><p>The flasks can now be sent for cleaning and autoclaving. The cell sediment in the pots is expected to have a volume of <span class=\"component-amount\">3 mL</span>  – <span class=\"component-amount\">6 mL</span> .</p><p></p></div> </figure><p></p>",
                "<p>Add <span class=\"component-amount\">18 mL</span>  of cold cell collection buffer to the sediment.</p><p></p>",
                "<p>Transfer the <span class=\"component-amount\">1 L</span>  pots to the Infors incubator and set the temperature to  <span class=\"component-temperature\">14 °C</span>  and the rotation to  <span class=\"component-centrifuge\">110 rpm,  °C, </span> .</p><p></p>",
                "<p>Leave the pots for <span class=\"component-duration\">00:30:00</span> , after which time the cell sediment should have completely resuspended.</p><p></p>",
                "<p>Pool all suspensions into one of the 12 pots using a <span class=\"component-amount\">25 mL</span>  pipette and a good pipettor.</p><p></p>",
                "<p>If any of the sediments has not well resuspended, pipette up and down close to the bottom of the pots.</p>",
                "<p>Supplement NaCl to  <span class=\"component-concentration\">0.4 Molarity (M)</span>  final concentration and add glycerol to 10% final concentration and mix well.</p><p></p>",
                "<p>Aliquot <span class=\"component-amount\">45 mL</span>  into <span class=\"component-amount\">50 mL</span>  centrifuge vials and freeze them in liquid nitrogen for <span class=\"component-duration\">00:20:00</span> .</p><p></p>",
                "<p>Store at  <span class=\"component-temperature\">-20 °C</span>  for up to <span class=\"component-duration\">672:00:00</span> . </p><figure><div class=\"component-note\"><p>The freezing and subsequent thawing step breaks up the cells and improves yield.</p></div> </figure><p></p><p></p>",
            ],
            stepDurations: [
                0,
                1500,
                0,
                0,
                0,
                1800,
                0,
                0,
                0,
                1200,
                2419200,
            ]
        ),
        Section(
            name: "Repurification and buffer exchange by Size Exclusion Chromatography",
            stepDescriptions: [
                "<p>Apply the protein to a Superdex 75 column, equilibrate this time in SEC buffer II.</p><figure><div class=\"component-note\"><p>This step removes the ATP and ADP, any remaining MST3 and replaces the buffer system. There are two important changes compared to SEC buffer I: firstly the buffer system is MES at <span class=\"component-ph\">pH 5.6</span>  and not Tris at <span class=\"component-ph\">pH 7.5</span> . This is to protonise the Rab10 protein in preparation for the next cation exchange step and Tris is not a suitable buffer system for cation exchange chromatography. Secondly, SEC buffer II does not contain L-arginine, which would interfere with the subsequent cation-exchange step. Figure 2 shows that the pRab10 protein elutes at <span class=\"component-amount\">85 mL</span> , exactly where the Rab10 would elute.</p><figure><img class=\"component-image\" src=\"https://content.protocols.io/files/dv27bixhp.jpg\" alt=\"image.png\" width=\"550\" height=\"381\"> </figure><p></p></div> </figure><p></p>",
            ],
            stepDurations: [
                0,
            ]
        ),
        Section(
            name: "Set up cells and induce expression",
            stepDescriptions: [
                "<p>Decant 12 x <span class=\"component-amount\">1 L</span>  LB broth medium into 12 x <span class=\"component-amount\">2 L</span>  conical flasks.</p><p></p>",
                "<p>Supplement each flask/litre with <span class=\"component-amount\">1 mL</span>  of  <span class=\"component-concentration\">50 mg/mL</span>  Kanamycin Monosulphate.</p><p></p>",
                "<p>Mix and add <span class=\"component-amount\">10 mL</span>  – <span class=\"component-amount\">25 mL</span>  of the overnight culture into each flask.</p><p></p>",
                "<p>Incubate for <span class=\"component-duration\">04:00:00</span>  at  <span class=\"component-temperature\">37 °C</span> , using an Infors Shaker-Incubator set at  <span class=\"component-centrifuge\">200 rpm,  °C, </span> .</p><p></p>",
                "<p>Sample two or three of the expressions by removing <span class=\"component-amount\">1 mL</span>  medium and comparing the optical density at <span class=\"component-amount\">600 nm</span>  with fresh LB medium, using a WPA cell densitometer or a spectrometer.</p><p></p>",
                "<p>When the OD<sub>600</sub> has reached 0.7-0.9, change the temperature setting of the Infors incubator to  <span class=\"component-temperature\">16 °C</span>  and incubate the cells for at least another hour, all the while shaking at  <span class=\"component-centrifuge\">200 rpm,  °C, </span> .</p><p></p>",
                "<p>When the flasks have cooled down to  <span class=\"component-temperature\">20 °C</span>  or lower, induce Rab10 expression by supplementing the medium with  <span class=\"component-concentration\">0.1 millimolar (mM)</span>  IPTG, e.g. with <span class=\"component-amount\">100 µL</span>  of a  <span class=\"component-concentration\">1 Molarity (M)</span>  IPTG stock solution to each litre.</p><p></p>",
                "<p>Leave the cells to express the protein for <span class=\"component-duration\">Overnight</span>  at  <span class=\"component-temperature\">16 °C</span> .</p><p></p>",
            ],
            stepDurations: [
                0,
                0,
                0,
                14400,
                0,
                0,
                0,
                14400,
            ]
        ),
    ]

    static func seed(into context: ModelContext) {
        let protocolModel = CachedProtocol(serverID: 1, protocolTitle: "Expression and purification of Rab10 (1-181)", enabled: true)
        context.insert(protocolModel)
        var stepServerID: Int64 = 1
        for (sectionIndex, section) in sections.enumerated() {
            let sectionModel = CachedProtocolSection(serverID: Int64(sectionIndex + 1), sectionDescription: section.name, order: sectionIndex, protocolModel: protocolModel)
            context.insert(sectionModel)
            for (stepIndex, description) in section.stepDescriptions.enumerated() {
                let step = CachedProtocolStep(serverID: stepServerID, stepDescription: description, order: stepIndex, stepDuration: section.stepDurations[stepIndex], section: sectionModel)
                context.insert(step)
                stepServerID += 1
            }
        }
        try? context.save()
    }
}
