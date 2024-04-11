import 'dart:typed_data';
import 'package:example/widgets/chat_input_box.dart';
import 'package:example/widgets/item_image_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:langchain_pinecone/langchain_pinecone.dart';
import 'package:lottie/lottie.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:langchain/langchain.dart';
import 'package:langchain_pinecone/langchain_pinecone.dart';
import 'package:uuid/uuid.dart';

class SectionTextStreamInput extends StatefulWidget {
  const SectionTextStreamInput({super.key});

  @override
  State<SectionTextStreamInput> createState() => _SectionTextInputStreamState();
}

class _SectionTextInputStreamState extends State<SectionTextStreamInput> {
  final openaiApiKey = "";
  final pineconeApiKey = "";
  late OpenAIEmbeddings embeddings;
  late Pinecone vectorStore;
  final ImagePicker picker = ImagePicker();
  final controller = TextEditingController();
  final gemini = Gemini.instance;
  String? searchedText,
      // result,
      _finishReason;

  List<Uint8List>? images;

  String? get finishReason => _finishReason;

  set finishReason(String? set) {
    if (set != _finishReason) {
      setState(() => _finishReason = set);
    }
  }

  @override
  Widget build(BuildContext context) {
    embeddings = OpenAIEmbeddings(apiKey: openaiApiKey);
    vectorStore = Pinecone(
      apiKey: pineconeApiKey,
      indexName: 'danjob',
      embeddings: embeddings,
    );
    return Column(
      children: [
        if (searchedText != null)
          MaterialButton(
              color: Colors.blue.shade700,
              onPressed: () {
                setState(() {
                  searchedText = null;
                  finishReason = null;
                  // result = null;
                });
              },
              child: Text('search: $searchedText')),
        Expanded(child: GeminiResponseTypeView(
          builder: (context, child, response, loading) {
            if (loading) {
              return Lottie.asset('assets/lottie/ai.json');
            }

            if (response != null) {
              return Markdown(
                data: response,
                selectable: true,
              );
            } else {
              return const Center(child: Text('Search something!'));
            }
          },
        )),

        /// if the returned finishReason isn't STOP
        if (finishReason != null) Text(finishReason!),

        if (images != null)
          Container(
            height: 120,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            child: Card(
              child: ListView.builder(
                itemBuilder: (context, index) => ItemImageView(
                  bytes: images!.elementAt(index),
                ),
                itemCount: images!.length,
                scrollDirection: Axis.horizontal,
              ),
            ),
          ),

        /// imported from local widgets
        ChatInputBox(
          controller: controller,
          onClickCamera: () {
            picker.pickMultiImage().then((value) async {
              final imagesBytes = <Uint8List>[];
              for (final file in value) {
                imagesBytes.add(await file.readAsBytes());
              }

              if (imagesBytes.isNotEmpty) {
                setState(() {
                  images = imagesBytes;
                });
              }
            });
          },
          onSend: () {
            print("stream log");
            if (controller.text.isNotEmpty) {
              print('request');

              searchedText = controller.text;
              controller.clear();
              gemini
                  .streamGenerateContent(searchedText!, images: images)
                  .handleError((e) {
                if (e is GeminiException) {
                  print(e);
                }
              }).listen((value) {
                setState(() {
                  images = null;
                });
                // result = (result ?? '') + (value.output ?? '');
                if (value.finishReason != 'STOP') {

                  finishReason = 'Finish reason is `${value.finishReason}`';
                }else{
                  print("finished reason " + value.finishReason.toString());
                  insertInVectorDB(searchedText!, value.output.toString());
                  print("finished output " + value.output.toString());
                }
              });
            }
          },
        )
      ],
    );
  }

  Future<void> insertInVectorDB(String query, String output) async {
    var uuid = Uuid();
    await vectorStore.addDocuments(
      documents:  [
        Document(
          id: uuid.v4(),
          pageContent: query + " Response: " + output,
          metadata: {'category': 'chat'},
        ),
      ],
    );

    // Query the vector store
    final res = await vectorStore.similaritySearch(
      query: 'What is study?',
      config: const PineconeSimilaritySearch(
        k: 2,
        scoreThreshold: 0.5,
        filter: {'category': 'chat'},
      ),
    );
    print(res);
  }
}


