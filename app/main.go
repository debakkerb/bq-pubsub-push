package main

import (
	"cloud.google.com/go/pubsub"
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"log"
)

type Person struct {
	FirstName string `xml:"firstName"`
	LastName  string `xml:"lastName"`
}

type PersonMessage struct {
	FirstName string `json:"firstName"`
	LastName  string `json:"lastName"`
	RawXml    string `json:"rawXml"`
}

func main() {
	projectID := "bdb-org-cicd"
	topicName := "bq-conn-topic"

	person := Person{
		FirstName: "John",
		LastName:  "Doe",
	}

	xmlData, err := xml.MarshalIndent(person, "", "  ")
	if err != nil {
		log.Fatalf("failed to marshal xml - %v", err)
	}

	xmlData = append([]byte(xml.Header), xmlData...)
	xmlString := string(xmlData)

	fmt.Printf("XML to be published:\n%s\n", xmlData)

	personMessage := PersonMessage{
		FirstName: person.FirstName,
		LastName:  person.LastName,
		RawXml:    xmlString,
	}

	jsonData, err := json.Marshal(personMessage)
	if err != nil {
		log.Fatalf("failed to marshal json - %v", err)
	}
	fmt.Printf("json to be published: \n%s\n", jsonData)

	ctx := context.Background()
	if err := publishXML(ctx, projectID, topicName, jsonData); err != nil {
		log.Fatalf("failed to publish message %v", err)
	}

	fmt.Println("Message published")
}

func publishXML(ctx context.Context, projectID, topicID string, jsonData []byte) error {
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return fmt.Errorf("pubsub.NewClient: %v", err)
	}
	defer client.Close()

	topic := client.Topic(topicID)
	defer topic.Stop()

	result := topic.Publish(ctx, &pubsub.Message{
		Data: jsonData,
		Attributes: map[string]string{
			"content-type": "application/json",
		},
	})

	id, err := result.Get(ctx)
	if err != nil {
		return fmt.Errorf("failed to publish %v", err)
	}

	fmt.Printf("published message with id %s\n", id)

	return nil
}
